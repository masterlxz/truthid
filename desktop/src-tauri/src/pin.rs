use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::single_slot_channel::{self, SingleSlotChannel};

/// Tempo que um POST /truthid/v1/pin fica pendurado esperando o usuário
/// aprovar/rejeitar antes de devolver 408. Toda requisição passa por aqui —
/// não existe caminho rápido sem aprovação (decisão do dono do projeto:
/// aprovação por chamada, mesmo padrão do /sign-request/sign-message, em vez
/// de autorização única por app com teto de uso).
pub const PIN_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

// ---------------------------------------------------------------------------
// Tipos do protocolo HTTP
// ---------------------------------------------------------------------------

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PinRequestBody {
    #[serde(default)]
    pub app_name: String,
    #[serde(default)]
    pub content_base64: String,
}

/// O que vai pro evento Tauri e pro comando get_pending_pin_request — tudo
/// que o frontend precisa pra renderizar a tela de aprovação. Não inclui o
/// conteúdo em si (o TruthID nunca precisa mostrar/inspecionar o blob
/// cifrado pra decidir se aprova o app a usar a wallet Arweave local).
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PinApprovalPayload {
    pub id: String,
    pub app_name: String,
    pub expires_at_ms: i64,
}

single_slot_channel::impl_payload_id!(PinApprovalPayload);

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum PinDecision {
    Approved,
    Rejected,
}

pub enum PinOutcome {
    Pinned {
        cid: String,
        content_hash: String,
        providers_ok: Vec<String>,
        providers_failed: Vec<String>,
    },
    Rejected,
    Failed(String),
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PinResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub providers_ok: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub providers_failed: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl PinOutcome {
    pub fn into_response(self) -> (axum::http::StatusCode, PinResponse) {
        use axum::http::StatusCode;
        match self {
            PinOutcome::Pinned {
                cid,
                content_hash,
                providers_ok,
                providers_failed,
            } => (
                StatusCode::OK,
                PinResponse {
                    status: "pinned",
                    cid: Some(cid),
                    content_hash: Some(content_hash),
                    providers_ok: Some(providers_ok),
                    providers_failed: Some(providers_failed),
                    error: None,
                },
            ),
            PinOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                PinResponse {
                    status: "rejected",
                    cid: None,
                    content_hash: None,
                    providers_ok: None,
                    providers_failed: None,
                    error: None,
                },
            ),
            PinOutcome::Failed(error) => (
                StatusCode::BAD_GATEWAY,
                PinResponse {
                    status: "failed",
                    cid: None,
                    content_hash: None,
                    providers_ok: None,
                    providers_failed: None,
                    error: Some(error),
                },
            ),
            PinOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                PinResponse {
                    status: "timeout",
                    cid: None,
                    content_hash: None,
                    providers_ok: None,
                    providers_failed: None,
                    error: None,
                },
            ),
            PinOutcome::Busy => (
                StatusCode::CONFLICT,
                PinResponse {
                    status: "busy",
                    cid: None,
                    content_hash: None,
                    providers_ok: None,
                    providers_failed: None,
                    error: Some("another pin request is already pending".to_string()),
                },
            ),
            PinOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                PinResponse {
                    status: "invalid",
                    cid: None,
                    content_hash: None,
                    providers_ok: None,
                    providers_failed: None,
                    error: Some(error),
                },
            ),
        }
    }
}

// ---------------------------------------------------------------------------
// Núcleo do protocolo
// ---------------------------------------------------------------------------

/// Tipo público do slot — determinado por SingleSlotChannel, mesmo padrão de
/// `sign_message::SignMessageState`. Sem estado persistido nenhum (nada de
/// autorização por app/cota diária, removido junto com a decisão de
/// aprovação por chamada) — cada requisição é independente.
pub type PinState = SingleSlotChannel<PinApprovalPayload, PinDecision>;

/// Núcleo do protocolo — sem dependência de tauri::AppHandle, mesmo espírito
/// de sign_message::handle_incoming. `notify` é chamado pra toda requisição
/// válida, sempre — não há caminho que pina sem passar por aprovação humana.
/// `pin` é injetado pra este módulo ser testável sem HTTP real — é
/// assíncrono (não `FnOnce` síncrono como o `sign` de sign_message.rs)
/// porque `arweave::publish_pinned_content`, a implementação real, faz
/// chamadas HTTP pra rede Arweave.
pub async fn handle_incoming<F, Fut>(
    state: &PinState,
    body: PinRequestBody,
    notify: impl FnOnce(&PinApprovalPayload),
    pin: F,
) -> PinOutcome
where
    F: FnOnce(Vec<u8>) -> Fut,
    Fut: std::future::Future<Output = Result<(String, String, Vec<String>, Vec<String>), String>>,
{
    handle_incoming_with_timeout(state, body, notify, pin, PIN_REQUEST_TIMEOUT).await
}

async fn handle_incoming_with_timeout<F, Fut>(
    state: &PinState,
    body: PinRequestBody,
    notify: impl FnOnce(&PinApprovalPayload),
    pin: F,
    timeout: Duration,
) -> PinOutcome
where
    F: FnOnce(Vec<u8>) -> Fut,
    Fut: std::future::Future<Output = Result<(String, String, Vec<String>, Vec<String>), String>>,
{
    use base64::{engine::general_purpose::STANDARD, Engine as _};

    let app_name = body.app_name.trim().to_string();
    if app_name.is_empty() {
        return PinOutcome::Invalid("appName is required".to_string());
    }
    let content = match STANDARD.decode(&body.content_base64) {
        Ok(bytes) if !bytes.is_empty() => bytes,
        Ok(_) => return PinOutcome::Invalid("contentBase64 must not be empty".to_string()),
        Err(_) => return PinOutcome::Invalid("contentBase64 is not valid base64".to_string()),
    };

    let (payload, rx) = {
        let payload = PinApprovalPayload {
            id: single_slot_channel::random_id(),
            app_name,
            expires_at_ms: single_slot_channel::now_ms() + timeout.as_millis() as i64,
        };
        match state.try_park(payload).await {
            Ok(ok) => ok,
            Err(()) => return PinOutcome::Busy,
        }
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(PinDecision::Approved)) => match pin(content).await {
            Ok((cid, content_hash, providers_ok, providers_failed)) => PinOutcome::Pinned {
                cid,
                content_hash,
                providers_ok,
                providers_failed,
            },
            Err(e) => PinOutcome::Failed(e),
        },
        Ok(Ok(PinDecision::Rejected)) => PinOutcome::Rejected,
        Ok(Err(_)) => PinOutcome::Failed("frontend disconnected before responding".to_string()),
        Err(_) => {
            state.clear().await;
            PinOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_pin_request.
pub async fn current(state: &PinState) -> Option<PinApprovalPayload> {
    state.current().await
}

/// Usado por respond_to_pin_request, depois do usuário aprovar/rejeitar.
pub async fn resolve(state: &PinState, id: &str, decision: PinDecision) -> Result<(), String> {
    state.resolve(id, decision).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn body(app_name: &str, content: &[u8]) -> PinRequestBody {
        use base64::{engine::general_purpose::STANDARD, Engine as _};
        PinRequestBody {
            app_name: app_name.to_string(),
            content_base64: STANDARD.encode(content),
        }
    }

    async fn fake_pin(
        content: Vec<u8>,
    ) -> Result<(String, String, Vec<String>, Vec<String>), String> {
        Ok((
            format!("cid-{}", content.len()),
            "0xhash".to_string(),
            vec!["arweave".to_string()],
            vec![],
        ))
    }

    async fn wait_for_pending(state: &PinState) -> PinApprovalPayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn parks_for_approval_then_pins_on_approve() {
        let state = Arc::new(PinState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(
                &state_bg,
                body("Practice Valuation", b"hello"),
                |_| {},
                fake_pin,
            )
            .await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.app_name, "Practice Valuation");

        resolve(&state, &payload.id, PinDecision::Approved)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, PinOutcome::Pinned { .. }));
    }

    #[tokio::test]
    async fn rejected_decision_never_calls_pin() {
        let state = Arc::new(PinState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(
                &state_bg,
                body("Sketchy App", b"hello"),
                |_| {},
                |_| async { panic!("pin should never be called on rejection") },
            )
            .await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, PinDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, PinOutcome::Rejected));
    }

    /// Regressão do modelo de consentimento (decisão do dono do projeto:
    /// aprovação por chamada, sem cota/autorização persistida) — duas
    /// chamadas seguidas do mesmo app pedem aprovação as duas vezes, nenhum
    /// caminho rápido silencioso depois da primeira. `wait_for_pending` só
    /// retorna depois que a 2ª chamada de fato parqueia de novo — se
    /// existisse um caminho rápido pós-1ª-aprovação, ela nunca parquearia e
    /// este teste travaria até o timeout de `handle_incoming`.
    #[tokio::test]
    async fn same_app_requires_approval_again_on_a_second_call() {
        let state = Arc::new(PinState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, body("Practice Valuation", b"hello"), |_| {}, fake_pin)
                .await
        });
        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, PinDecision::Approved)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");

        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(
                &state_bg,
                body("Practice Valuation", b"world"),
                |_| {},
                fake_pin,
            )
            .await
        });
        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, PinDecision::Approved)
            .await
            .expect("resolve should succeed");
        let outcome = handle.await.expect("task should not panic");

        assert!(matches!(outcome, PinOutcome::Pinned { .. }));
    }

    #[tokio::test]
    async fn concurrent_second_pending_request_is_busy() {
        let state = Arc::new(PinState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, body("App One", b"hello"), |_| {}, fake_pin).await
        });

        let payload = wait_for_pending(&state).await;

        let second = handle_incoming(&state, body("App Two", b"world"), |_| {}, fake_pin).await;
        assert!(matches!(second, PinOutcome::Busy));

        resolve(&state, &payload.id, PinDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn invalid_body_never_notifies_and_never_parks() {
        let state = PinState::default();

        let mut notified = false;
        let outcome =
            handle_incoming(&state, body("", b"hello"), |_| notified = true, fake_pin).await;
        assert!(matches!(outcome, PinOutcome::Invalid(_)));
        assert!(!notified);
        assert!(current(&state).await.is_none());

        let mut bad = body("App", b"hello");
        bad.content_base64 = "not-valid-base64!!".to_string();
        let outcome = handle_incoming(&state, bad, |_| notified = true, fake_pin).await;
        assert!(matches!(outcome, PinOutcome::Invalid(_)));
        assert!(!notified);
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_pending_state() {
        let state = PinState::default();

        let outcome = handle_incoming_with_timeout(
            &state,
            body("Practice Valuation", b"hello"),
            |_| {},
            fake_pin,
            Duration::from_millis(50),
        )
        .await;

        assert!(matches!(outcome, PinOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rand::RngCore;
use serde::{Deserialize, Serialize};
use tokio::sync::{oneshot, Mutex};

/// Tempo que um POST /truthid/v1/sign-message fica pendurado esperando o
/// usuário aprovar/rejeitar antes de devolver 408. Mesma constante de
/// `sign_request::SIGN_REQUEST_TIMEOUT`, mas própria deste módulo — cada
/// canal do local_signer_server é auto-contido, sem depender um do outro.
pub const SIGN_MESSAGE_TIMEOUT: Duration = Duration::from_secs(300);

fn random_id() -> String {
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// `purpose` é um identificador curto, não texto livre — evita mensagens
/// exibidas na tela de aprovação com quebras de linha ou caracteres que
/// confundam a UI, e mantém a domain separation entre propósitos legível.
fn is_valid_purpose(purpose: &str) -> bool {
    !purpose.is_empty()
        && purpose.len() <= 64
        && purpose
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.')
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SignMessageBody {
    #[serde(default)]
    pub app_name: String,
    #[serde(default)]
    pub purpose: String,
}

/// O que vai pro evento Tauri e pro comando get_pending_sign_message — tudo
/// que o frontend precisa pra renderizar a tela de aprovação, incluindo a
/// `message` final já montada (nunca escondida do usuário — mesma filosofia
/// de transparência da correção do SignRequestModal, Sessão 104).
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SignMessagePayload {
    pub id: String,
    pub app_name: String,
    pub purpose: String,
    pub message: String,
    pub expires_at_ms: i64,
}

/// O que o frontend manda de volta via respond_to_sign_message, depois do
/// usuário decidir. Ao contrário do sign-request, não existe variante
/// Executed/Failed vinda do frontend — a assinatura em si acontece no Rust,
/// dentro de handle_incoming, depois de receber Approved.
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum SignMessageDecision {
    Approved,
    Rejected,
}

/// O que handle_incoming devolve pro handler HTTP mapear pra status code.
pub enum SignMessageOutcome {
    Signed { message: String, signature: String },
    Rejected,
    Failed(String),
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SignMessageResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl SignMessageOutcome {
    pub fn into_response(self) -> (axum::http::StatusCode, SignMessageResponse) {
        use axum::http::StatusCode;
        match self {
            SignMessageOutcome::Signed { message, signature } => (
                StatusCode::OK,
                SignMessageResponse {
                    status: "signed",
                    message: Some(message),
                    signature: Some(signature),
                    error: None,
                },
            ),
            SignMessageOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                SignMessageResponse {
                    status: "rejected",
                    message: None,
                    signature: None,
                    error: None,
                },
            ),
            SignMessageOutcome::Failed(error) => (
                StatusCode::BAD_GATEWAY,
                SignMessageResponse {
                    status: "failed",
                    message: None,
                    signature: None,
                    error: Some(error),
                },
            ),
            SignMessageOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                SignMessageResponse {
                    status: "timeout",
                    message: None,
                    signature: None,
                    error: None,
                },
            ),
            SignMessageOutcome::Busy => (
                StatusCode::CONFLICT,
                SignMessageResponse {
                    status: "busy",
                    message: None,
                    signature: None,
                    error: Some("another sign-message request is already pending".to_string()),
                },
            ),
            SignMessageOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                SignMessageResponse {
                    status: "invalid",
                    message: None,
                    signature: None,
                    error: Some(error),
                },
            ),
        }
    }
}

struct PendingMessage {
    payload: SignMessagePayload,
    responder: oneshot::Sender<SignMessageDecision>,
}

/// tokio::sync::Mutex (não std): o guard atravessa .await tanto em
/// handle_incoming (espera o oneshot) quanto em resolve/current.
#[derive(Default)]
pub struct SignMessageState(Mutex<Option<PendingMessage>>);

/// Núcleo do protocolo de aprovação — deliberadamente sem nenhuma dependência
/// de tauri::AppHandle, mesmo espírito de sign_request::handle_incoming.
/// `notify` avisa o frontend do pedido pendente; `sign` só é chamado depois
/// de receber Approved, e é injetado (não chamado direto aqui) pra este
/// módulo ser testável sem tocar o keyring do SO.
pub async fn handle_incoming(
    state: &SignMessageState,
    body: SignMessageBody,
    notify: impl FnOnce(&SignMessagePayload),
    sign: impl FnOnce(&str) -> Result<String, String>,
) -> SignMessageOutcome {
    handle_incoming_with_timeout(state, body, notify, sign, SIGN_MESSAGE_TIMEOUT).await
}

async fn handle_incoming_with_timeout(
    state: &SignMessageState,
    body: SignMessageBody,
    notify: impl FnOnce(&SignMessagePayload),
    sign: impl FnOnce(&str) -> Result<String, String>,
    timeout: Duration,
) -> SignMessageOutcome {
    let app_name = body.app_name.trim().to_string();
    if app_name.is_empty() {
        return SignMessageOutcome::Invalid("appName is required".to_string());
    }
    if !is_valid_purpose(&body.purpose) {
        return SignMessageOutcome::Invalid(
            "purpose must be 1-64 chars of [A-Za-z0-9_.-]".to_string(),
        );
    }

    // Mensagem final montada aqui, nunca vinda direto do chamador — garante
    // domain separation entre apps/propósitos e nunca colide com a mensagem
    // interna do password manager ("TruthID Vault Key v1").
    let message = format!("TruthID Message Signing: {}:{}", app_name, body.purpose);

    let (payload, rx) = {
        let mut guard = state.0.lock().await;
        if guard.is_some() {
            return SignMessageOutcome::Busy;
        }

        let payload = SignMessagePayload {
            id: random_id(),
            app_name,
            purpose: body.purpose,
            message,
            expires_at_ms: now_ms() + timeout.as_millis() as i64,
        };
        let (tx, rx) = oneshot::channel();
        *guard = Some(PendingMessage { payload: payload.clone(), responder: tx });
        (payload, rx)
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(SignMessageDecision::Approved)) => match sign(&payload.message) {
            Ok(signature) => SignMessageOutcome::Signed { message: payload.message, signature },
            Err(error) => SignMessageOutcome::Failed(error),
        },
        Ok(Ok(SignMessageDecision::Rejected)) => SignMessageOutcome::Rejected,
        Ok(Err(_)) => {
            SignMessageOutcome::Failed("frontend disconnected before responding".to_string())
        }
        Err(_) => {
            // Já estourou o timeout — limpa o slot. Se respond_to_sign_message
            // for chamado depois disso com o mesmo id, resolve() não vai achar
            // o pedido e devolve erro (o frontend trata como "já expirou").
            state.0.lock().await.take();
            SignMessageOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_sign_message — cobre o caso da janela do Desktop sem
/// foco no momento do app.emit (o frontend também consulta isso ao montar,
/// além de escutar o evento).
pub async fn current(state: &SignMessageState) -> Option<SignMessagePayload> {
    state.0.lock().await.as_ref().map(|p| p.payload.clone())
}

/// Usado por respond_to_sign_message, depois do usuário aprovar/rejeitar.
/// Confere que o id bate com o pedido atual antes de consumir, pra não
/// resolver o pedido errado numa race rara (ex: um pedido expirou e outro já
/// parqueou no lugar dele).
pub async fn resolve(
    state: &SignMessageState,
    id: &str,
    decision: SignMessageDecision,
) -> Result<(), String> {
    let mut guard = state.0.lock().await;
    match guard.take() {
        Some(pending) if pending.payload.id == id => {
            let _ = pending.responder.send(decision);
            Ok(())
        }
        Some(pending) => {
            *guard = Some(pending);
            Err("id does not match the currently pending sign-message request".to_string())
        }
        None => Err("no pending sign-message request (it may have already expired)".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn valid_body() -> SignMessageBody {
        SignMessageBody {
            app_name: "Practice Valuation".to_string(),
            purpose: "vault-sync-key".to_string(),
        }
    }

    fn fake_sign(message: &str) -> Result<String, String> {
        Ok(format!("0xfakesig:{message}"))
    }

    async fn wait_for_pending(state: &SignMessageState) -> SignMessagePayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn handle_incoming_waits_for_resolve_and_signs_on_approve() {
        let state = Arc::new(SignMessageState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}, fake_sign).await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.message, "TruthID Message Signing: Practice Valuation:vault-sync-key");

        resolve(&state, &payload.id, SignMessageDecision::Approved)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        match outcome {
            SignMessageOutcome::Signed { message, signature } => {
                assert_eq!(message, payload.message);
                assert_eq!(signature, format!("0xfakesig:{}", payload.message));
            }
            _ => panic!("expected Signed outcome"),
        }
    }

    #[tokio::test]
    async fn rejected_decision_never_calls_sign() {
        let state = Arc::new(SignMessageState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}, |_| {
                panic!("sign should never be called on rejection")
            })
            .await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, SignMessageDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, SignMessageOutcome::Rejected));
    }

    #[tokio::test]
    async fn concurrent_second_request_is_busy() {
        let state = Arc::new(SignMessageState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}, fake_sign).await
        });

        let payload = wait_for_pending(&state).await;

        let second = handle_incoming(&state, valid_body(), |_| {}, fake_sign).await;
        assert!(matches!(second, SignMessageOutcome::Busy));

        resolve(&state, &payload.id, SignMessageDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn resolve_with_wrong_id_does_not_consume_pending_request() {
        let state = Arc::new(SignMessageState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}, fake_sign).await
        });

        let payload = wait_for_pending(&state).await;

        let err = resolve(&state, "not-the-real-id", SignMessageDecision::Rejected).await;
        assert!(err.is_err());
        assert!(current(&state).await.is_some(), "pending request should survive a mismatched id");

        resolve(&state, &payload.id, SignMessageDecision::Rejected)
            .await
            .expect("resolve should succeed with the right id");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn invalid_body_never_notifies_and_never_parks() {
        let state = SignMessageState::default();

        let mut body = valid_body();
        body.app_name = "".to_string();
        let mut notified = false;
        let outcome = handle_incoming(&state, body, |_| notified = true, fake_sign).await;
        assert!(matches!(outcome, SignMessageOutcome::Invalid(_)));
        assert!(!notified);
        assert!(current(&state).await.is_none());

        let mut body = valid_body();
        body.purpose = "has a space".to_string();
        let outcome = handle_incoming(&state, body, |_| notified = true, fake_sign).await;
        assert!(matches!(outcome, SignMessageOutcome::Invalid(_)));
        assert!(!notified);
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_state() {
        let state = SignMessageState::default();

        let outcome = handle_incoming_with_timeout(
            &state,
            valid_body(),
            |_| {},
            fake_sign,
            Duration::from_millis(50),
        )
        .await;

        assert!(matches!(outcome, SignMessageOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}

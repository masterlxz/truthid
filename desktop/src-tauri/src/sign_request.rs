use std::time::Duration;

use axum::http::StatusCode;
use serde::{Deserialize, Serialize};

use crate::single_slot_channel::{self, SingleSlotChannel};

/// Tempo que um POST /truthid/v1/sign-request fica pendurado esperando o
/// usuário aprovar/rejeitar antes de devolver 408. Mora no Rust (não no
/// frontend) porque precisa sobreviver a uma UI travada ou o usuário nunca
/// decidir.
pub const SIGN_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

fn default_value() -> String {
    "0".to_string()
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SignRequestBody {
    #[serde(default)]
    pub app_name: String,
    #[serde(default)]
    pub dest: String,
    #[serde(default = "default_value")]
    pub value: String,
    #[serde(default)]
    pub call_data: String,
    #[serde(default)]
    pub function_signature: String,
}

/// O que vai pro evento Tauri e pro comando get_pending_sign_request — tudo
/// que o frontend precisa pra renderizar a tela de aprovação. Rust nunca
/// decodifica callData/functionSignature (isso é trabalho do viem no
/// frontend) — só repassa cru, mesma postura da fatia 2a.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SignRequestPayload {
    pub id: String,
    pub app_name: String,
    pub dest: String,
    pub value: String,
    pub call_data: String,
    pub function_signature: String,
    pub expires_at_ms: i64,
}

single_slot_channel::impl_payload_id!(SignRequestPayload);

/// O que o frontend manda de volta via respond_to_sign_request, depois do
/// usuário decidir (ou depois de tentar executar e falhar).
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum SignRequestDecision {
    #[serde(rename_all = "camelCase")]
    Executed {
        user_op_hash: String,
        transaction_hash: Option<String>,
    },
    Rejected,
    #[serde(rename_all = "camelCase")]
    Failed { error: String },
}

/// O que handle_incoming devolve pro handler HTTP mapear pra status code.
pub enum SignRequestOutcome {
    Executed {
        user_op_hash: String,
        transaction_hash: Option<String>,
    },
    Rejected,
    Failed(String),
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SignRequestResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_op_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transaction_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl SignRequestOutcome {
    pub fn into_response(self) -> (StatusCode, SignRequestResponse) {
        match self {
            SignRequestOutcome::Executed { user_op_hash, transaction_hash } => (
                StatusCode::OK,
                SignRequestResponse {
                    status: "executed",
                    user_op_hash: Some(user_op_hash),
                    transaction_hash,
                    error: None,
                },
            ),
            SignRequestOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                SignRequestResponse {
                    status: "rejected",
                    user_op_hash: None,
                    transaction_hash: None,
                    error: None,
                },
            ),
            SignRequestOutcome::Failed(error) => (
                StatusCode::BAD_GATEWAY,
                SignRequestResponse {
                    status: "failed",
                    user_op_hash: None,
                    transaction_hash: None,
                    error: Some(error),
                },
            ),
            SignRequestOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                SignRequestResponse {
                    status: "timeout",
                    user_op_hash: None,
                    transaction_hash: None,
                    error: None,
                },
            ),
            SignRequestOutcome::Busy => (
                StatusCode::CONFLICT,
                SignRequestResponse {
                    status: "busy",
                    user_op_hash: None,
                    transaction_hash: None,
                    error: Some("another sign request is already pending".to_string()),
                },
            ),
            SignRequestOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                SignRequestResponse {
                    status: "invalid",
                    user_op_hash: None,
                    transaction_hash: None,
                    error: Some(error),
                },
            ),
        }
    }
}

/// Tipo público do slot — usado por lib.rs como `State<'_, ...>` e por
/// local_signer_server.rs como `Arc<...>`.
pub type SignRequestState = SingleSlotChannel<SignRequestPayload, SignRequestDecision>;

/// Núcleo do protocolo de aprovação — deliberadamente sem nenhuma dependência
/// de tauri::AppHandle. `notify` é injetado como closure só pra poder testar
/// parking/single-flight/timeout em #[tokio::test] puro, sem precisar de um
/// app Tauri rodando.
pub async fn handle_incoming(
    state: &SignRequestState,
    body: SignRequestBody,
    notify: impl FnOnce(&SignRequestPayload),
) -> SignRequestOutcome {
    handle_incoming_with_timeout(state, body, notify, SIGN_REQUEST_TIMEOUT).await
}

async fn handle_incoming_with_timeout(
    state: &SignRequestState,
    body: SignRequestBody,
    notify: impl FnOnce(&SignRequestPayload),
    timeout: Duration,
) -> SignRequestOutcome {
    if body.app_name.trim().is_empty()
        || body.dest.trim().is_empty()
        || body.call_data.trim().is_empty()
        || body.function_signature.trim().is_empty()
    {
        return SignRequestOutcome::Invalid(
            "appName, dest, callData and functionSignature are required".to_string(),
        );
    }

    let (payload, rx) = {
        let payload = SignRequestPayload {
            id: single_slot_channel::random_id(),
            app_name: body.app_name,
            dest: body.dest,
            value: body.value,
            call_data: body.call_data,
            function_signature: body.function_signature,
            expires_at_ms: single_slot_channel::now_ms() + timeout.as_millis() as i64,
        };
        match state.try_park(payload).await {
            Ok(ok) => ok,
            Err(()) => return SignRequestOutcome::Busy,
        }
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(SignRequestDecision::Executed { user_op_hash, transaction_hash })) => {
            SignRequestOutcome::Executed { user_op_hash, transaction_hash }
        }
        Ok(Ok(SignRequestDecision::Rejected)) => SignRequestOutcome::Rejected,
        Ok(Ok(SignRequestDecision::Failed { error })) => SignRequestOutcome::Failed(error),
        Ok(Err(_)) => {
            SignRequestOutcome::Failed("frontend disconnected before responding".to_string())
        }
        Err(_) => {
            state.clear().await;
            SignRequestOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_sign_request — cobre o caso da janela do Desktop
/// sem foco no momento do app.emit (o frontend também consulta isso ao
/// montar, além de escutar o evento).
pub async fn current(state: &SignRequestState) -> Option<SignRequestPayload> {
    state.current().await
}

/// Usado pelo frontend antes de executar a UserOp (gasta gas). Retorna true
/// se o pedido ainda está pendente (não expirou no lado Rust). Evita que
/// uma aprovação tardia (janela minimizada, setInterval throttled) envie uma
/// UserOperation pra Mainnet depois do caller já ter recebido 408.
pub async fn is_valid(state: &SignRequestState, id: &str) -> bool {
    state.is_valid(id).await
}

/// Usado por respond_to_sign_request, depois do usuário aprovar/rejeitar (ou
/// depois de uma tentativa de execução falhar). Confere que o id bate com o
/// pedido atual antes de consumir, pra não resolver o pedido errado numa
/// race rara (ex: um pedido expirou e outro já parqueou no lugar dele).
pub async fn resolve(
    state: &SignRequestState,
    id: &str,
    decision: SignRequestDecision,
) -> Result<(), String> {
    state.resolve(id, decision).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn valid_body() -> SignRequestBody {
        SignRequestBody {
            app_name: "Practice Valuation".to_string(),
            dest: "0x0000000000000000000000000000000000000001".to_string(),
            value: "0".to_string(),
            call_data: "0xa9059cbb".to_string(),
            function_signature: "transfer(address,uint256)".to_string(),
        }
    }

    async fn wait_for_pending(state: &SignRequestState) -> SignRequestPayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn handle_incoming_waits_for_resolve() {
        let state = Arc::new(SignRequestState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, SignRequestDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, SignRequestOutcome::Rejected));
    }

    #[tokio::test]
    async fn concurrent_second_request_is_busy() {
        let state = Arc::new(SignRequestState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;

        let second = handle_incoming(&state, valid_body(), |_| {}).await;
        assert!(matches!(second, SignRequestOutcome::Busy));

        resolve(&state, &payload.id, SignRequestDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn resolve_with_wrong_id_does_not_consume_pending_request() {
        let state = Arc::new(SignRequestState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, valid_body(), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;

        let err = resolve(&state, "not-the-real-id", SignRequestDecision::Rejected).await;
        assert!(err.is_err());
        assert!(current(&state).await.is_some(), "pending request should survive a mismatched id");

        resolve(&state, &payload.id, SignRequestDecision::Rejected)
            .await
            .expect("resolve should succeed with the right id");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn invalid_body_never_notifies_and_never_parks() {
        let state = SignRequestState::default();
        let mut body = valid_body();
        body.app_name = "".to_string();

        let mut notified = false;
        let outcome = handle_incoming(&state, body, |_| notified = true).await;

        assert!(matches!(outcome, SignRequestOutcome::Invalid(_)));
        assert!(!notified);
        assert!(current(&state).await.is_none());
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_state() {
        let state = SignRequestState::default();

        let outcome =
            handle_incoming_with_timeout(&state, valid_body(), |_| {}, Duration::from_millis(50))
                .await;

        assert!(matches!(outcome, SignRequestOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}
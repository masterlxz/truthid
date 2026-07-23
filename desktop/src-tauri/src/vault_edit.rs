use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::single_slot_channel::{self, SingleSlotChannel};
use crate::vault;

/// Tempo que um POST /truthid/v1/vault-edit fica pendurado esperando o
/// usuário aprovar/rejeitar antes de devolver 408 — mesmo valor de
/// `pin::PIN_REQUEST_TIMEOUT`. Diferente do `/pin`, aqui **todo** pedido
/// estaciona (sem cota/caminho rápido) — cada proposta de credencial nova
/// pede aprovação individual, mesma decisão já tomada no `/pin` cross-device
/// do Mobile (`pin_approval_screen.dart`: "sem sistema de cota/autorização
/// persistente... cada pedido cross-device pede aprovação individual").
pub const VAULT_EDIT_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

// ---------------------------------------------------------------------------
// Tipos do protocolo HTTP
// ---------------------------------------------------------------------------

/// Espelho de `vault::Passkey` — campo a campo, mesmo formato JSON (`rename_all`
/// não entra aqui, os dois usam snake_case cru, igual o resto do vault).
#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct PasskeyProposal {
    pub rp_id: String,
    pub credential_id_b64: String,
    pub user_handle_b64: String,
    pub private_key_hex: String,
    pub sign_count: u32,
    pub created_at: u64,
}

/// Corpo do POST — uma proposta de `VaultEntry` ainda sem `id` (o Device
/// decide o id na hora do merge, via `vault::Vault::upsert`). Sem
/// `app_name`: ao contrário do `/pin` (app terceiro qualquer), este canal só
/// é falado pela própria extensão TruthID, então não há "quem está pedindo"
/// pra mostrar na aprovação — só "o que está sendo proposto".
///
/// `pub_key` identifica o device que originou a proposta (endereço do
/// desktop local ou do mobile no caminho cross-device). Opcional: na rota
/// desktop loopback (localhost), pode vir `None` — o próprio Desktop é
/// controller, sempre tem permissão de escrita.
#[derive(Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct VaultEditRequestBody {
    #[serde(default)]
    pub site: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub passkey: Option<PasskeyProposal>,
    #[serde(default)]
    pub pub_key: Option<String>,
}

/// O que vai pro evento Tauri e pro comando get_pending_vault_edit_request.
/// Ao contrário de `pin::PinApprovalPayload` (conteúdo opaco, o TruthID nunca
/// precisa inspecionar o blob cifrado), aqui o payload inteiro É o que a UI
/// precisa mostrar (site/username/senha mascarada/badge de passkey) — nunca
/// sai do processo, é só IPC interno do Tauri.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct VaultEditApprovalPayload {
    pub id: String,
    pub entry: VaultEditRequestBody,
    pub expires_at_ms: i64,
    pub pub_key: Option<String>,
}

single_slot_channel::impl_payload_id!(VaultEditApprovalPayload);

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum VaultEditDecision {
    Approved,
    Rejected,
}

pub enum VaultEditOutcome {
    Approved { id: String },
    Rejected,
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultEditResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl VaultEditOutcome {
    pub fn into_response(self) -> (axum::http::StatusCode, VaultEditResponse) {
        use axum::http::StatusCode;
        match self {
            VaultEditOutcome::Approved { id } => (
                StatusCode::OK,
                VaultEditResponse {
                    status: "approved",
                    id: Some(id),
                    error: None,
                },
            ),
            VaultEditOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                VaultEditResponse {
                    status: "rejected",
                    id: None,
                    error: None,
                },
            ),
            VaultEditOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                VaultEditResponse {
                    status: "timeout",
                    id: None,
                    error: None,
                },
            ),
            VaultEditOutcome::Busy => (
                StatusCode::CONFLICT,
                VaultEditResponse {
                    status: "busy",
                    id: None,
                    error: Some("another vault edit request is already pending".to_string()),
                },
            ),
            VaultEditOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                VaultEditResponse {
                    status: "invalid",
                    id: None,
                    error: Some(error),
                },
            ),
        }
    }
}

// ---------------------------------------------------------------------------
// Núcleo do protocolo
// ---------------------------------------------------------------------------

/// Tipo público do slot — determinado por SingleSlotChannel.
pub type VaultEditState = SingleSlotChannel<VaultEditApprovalPayload, VaultEditDecision>;

/// Núcleo do protocolo — sem dependência de tauri::AppHandle, mesmo espírito
/// de pin::handle_incoming. Ao contrário do `/pin`, a resposta HTTP **não
/// espera o merge nem a publicação** — só confirma que o usuário aprovou; o
/// merge no vault local + pin no IPFS + assinatura da UserOperation rodam
/// depois, no clique do modal de aprovação (fora deste módulo, porque
/// dependem do fluxo de bundler que só existe em TS).
pub async fn handle_incoming(
    state: &VaultEditState,
    body: VaultEditRequestBody,
    notify: impl FnOnce(&VaultEditApprovalPayload),
) -> VaultEditOutcome {
    handle_incoming_with_timeout(state, body, notify, VAULT_EDIT_REQUEST_TIMEOUT).await
}

async fn handle_incoming_with_timeout(
    state: &VaultEditState,
    body: VaultEditRequestBody,
    notify: impl FnOnce(&VaultEditApprovalPayload),
    timeout: Duration,
) -> VaultEditOutcome {
    if body.site.trim().is_empty() {
        return VaultEditOutcome::Invalid("site is required".to_string());
    }
    if body.password.trim().is_empty() && body.passkey.is_none() {
        return VaultEditOutcome::Invalid(
            "at least one of password or passkey is required".to_string(),
        );
    }

    // Se o caller identifica um dispositivo (pub_key), verifica permissão
    // de escrita (canWriteVault) contra o vault local antes de estacionar.
    if let Some(ref pub_key) = body.pub_key {
        let v = match vault::load() {
            Ok(v) => v,
            Err(e) => return VaultEditOutcome::Invalid(format!("vault permission check failed: {e}")),
        };
        let perm = v.device_permissions.iter().find(|p| &p.pub_key == pub_key);
        match perm {
            None => {
                return VaultEditOutcome::Invalid(
                    format!("device {pub_key} has no vault permission — ask the identity controller to grant write access"),
                );
            }
            Some(p) if !p.can_write => {
                return VaultEditOutcome::Invalid(
                    "device does not have write permission for this vault".to_string(),
                );
            }
            _ => {} // tem permissão de escrita, segue
        }
    }

    let (payload, rx) = {
        let pub_key = body.pub_key.clone();

        let payload = VaultEditApprovalPayload {
            id: single_slot_channel::random_id(),
            entry: body,
            expires_at_ms: single_slot_channel::now_ms() + timeout.as_millis() as i64,
            pub_key,
        };
        match state.try_park(payload).await {
            Ok(ok) => ok,
            Err(()) => return VaultEditOutcome::Busy,
        }
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(VaultEditDecision::Approved)) => VaultEditOutcome::Approved { id: payload.id },
        Ok(Ok(VaultEditDecision::Rejected)) => VaultEditOutcome::Rejected,
        Ok(Err(_)) => VaultEditOutcome::Invalid(
            "frontend disconnected before responding".to_string(),
        ),
        Err(_) => {
            state.clear().await;
            VaultEditOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_vault_edit_request.
pub async fn current(state: &VaultEditState) -> Option<VaultEditApprovalPayload> {
    state.current().await
}

/// Usado por respond_to_vault_edit_request, depois do usuário aprovar/rejeitar.
pub async fn resolve(
    state: &VaultEditState,
    id: &str,
    decision: VaultEditDecision,
) -> Result<(), String> {
    state.resolve(id, decision).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn body(site: &str) -> VaultEditRequestBody {
        VaultEditRequestBody {
            site: site.to_string(),
            url: String::new(),
            username: "user".to_string(),
            password: "hunter2".to_string(),
            notes: String::new(),
            passkey: None,
            pub_key: None,
        }
    }

    async fn wait_for_pending(state: &VaultEditState) -> VaultEditApprovalPayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn approve_returns_approved_with_id() {
        let state = Arc::new(VaultEditState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, body("example.com"), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.entry.site, "example.com");

        resolve(&state, &payload.id, VaultEditDecision::Approved)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        match outcome {
            VaultEditOutcome::Approved { id } => assert_eq!(id, payload.id),
            _ => panic!("expected Approved"),
        }
    }

    #[tokio::test]
    async fn reject_returns_rejected() {
        let state = Arc::new(VaultEditState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, body("example.com"), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, VaultEditDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, VaultEditOutcome::Rejected));
    }

    #[tokio::test]
    async fn concurrent_second_pending_request_is_busy() {
        let state = Arc::new(VaultEditState::default());
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming(&state_bg, body("one.com"), |_| {}).await
        });

        let payload = wait_for_pending(&state).await;

        let second = handle_incoming(&state, body("two.com"), |_| {}).await;
        assert!(matches!(second, VaultEditOutcome::Busy));

        resolve(&state, &payload.id, VaultEditDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn invalid_body_never_notifies_and_never_parks() {
        let state = VaultEditState::default();

        let mut notified = false;
        let outcome = handle_incoming(&state, body(""), |_| notified = true).await;
        assert!(matches!(outcome, VaultEditOutcome::Invalid(_)));
        assert!(!notified);
        assert!(current(&state).await.is_none());

        let mut no_secret = body("example.com");
        no_secret.password = String::new();
        no_secret.passkey = None;
        let outcome = handle_incoming(&state, no_secret, |_| notified = true).await;
        assert!(matches!(outcome, VaultEditOutcome::Invalid(_)));
        assert!(!notified);
    }

    #[tokio::test]
    async fn passkey_only_body_is_valid_without_password() {
        let state = Arc::new(VaultEditState::default());
        let mut b = body("example.com");
        b.password = String::new();
        b.passkey = Some(PasskeyProposal {
            rp_id: "example.com".to_string(),
            credential_id_b64: "AAAA".to_string(),
            user_handle_b64: "BBBB".to_string(),
            private_key_hex: "00".repeat(32),
            sign_count: 0,
            created_at: 0,
        });

        let state_bg = state.clone();
        let handle = tokio::spawn(async move { handle_incoming(&state_bg, b, |_| {}).await });

        let payload = wait_for_pending(&state).await;
        assert!(payload.entry.passkey.is_some());

        resolve(&state, &payload.id, VaultEditDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_pending_state() {
        let state = VaultEditState::default();

        let outcome =
            handle_incoming_with_timeout(&state, body("example.com"), |_| {}, Duration::from_millis(50))
                .await;

        assert!(matches!(outcome, VaultEditOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}
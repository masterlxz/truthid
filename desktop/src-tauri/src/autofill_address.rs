use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::single_slot_channel::{self, SingleSlotChannel};
use crate::vault::{self, EntryType, VaultEntry};

/// Tempo que um POST /truthid/v1/autofill-address fica pendurado esperando o
/// usuário escolher/rejeitar — mesmo valor de `vault_edit::VAULT_EDIT_REQUEST_TIMEOUT`.
pub const AUTOFILL_ADDRESS_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

// ---------------------------------------------------------------------------
// Tipos do protocolo HTTP
// ---------------------------------------------------------------------------

/// Um endereço salvo, candidato a preencher o formulário. `entry_id` identifica
/// a entrada do Vault de origem — é o que o frontend devolve em `Approved` pra
/// dizer qual dos N candidatos o usuário escolheu (o Rust já tem os dados
/// completos, não precisa que o frontend os reenvie).
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AutofillAddressCandidate {
    pub entry_id: String,
    pub data: vault::AddressData,
}

/// O que vai pro evento Tauri e pro comando get_pending_autofill_address_request.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AutofillAddressApprovalPayload {
    pub id: String,
    pub candidates: Vec<AutofillAddressCandidate>,
    pub expires_at_ms: i64,
}

single_slot_channel::impl_payload_id!(AutofillAddressApprovalPayload);

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum AutofillAddressDecision {
    Approved { entry_id: String },
    Rejected,
}

pub enum AutofillAddressOutcome {
    // Boxed — AddressData tem 9 campos String, deixando essa variante bem
    // maior que as outras e disparando clippy::large_enum_variant.
    Filled(Box<vault::AddressData>),
    NoAddresses,
    Rejected,
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AutofillAddressResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub address: Option<vault::AddressData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl AutofillAddressOutcome {
    pub fn into_response(self) -> (axum::http::StatusCode, AutofillAddressResponse) {
        use axum::http::StatusCode;
        match self {
            AutofillAddressOutcome::Filled(address) => (
                StatusCode::OK,
                AutofillAddressResponse {
                    status: "filled",
                    address: Some(*address),
                    error: None,
                },
            ),
            AutofillAddressOutcome::NoAddresses => (
                StatusCode::OK,
                AutofillAddressResponse {
                    status: "no-addresses",
                    address: None,
                    error: None,
                },
            ),
            AutofillAddressOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                AutofillAddressResponse {
                    status: "rejected",
                    address: None,
                    error: None,
                },
            ),
            AutofillAddressOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                AutofillAddressResponse {
                    status: "timeout",
                    address: None,
                    error: None,
                },
            ),
            AutofillAddressOutcome::Busy => (
                StatusCode::CONFLICT,
                AutofillAddressResponse {
                    status: "busy",
                    address: None,
                    error: Some("another autofill request is already pending".to_string()),
                },
            ),
            AutofillAddressOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                AutofillAddressResponse {
                    status: "invalid",
                    address: None,
                    error: Some(error),
                },
            ),
        }
    }
}

// ---------------------------------------------------------------------------
// Núcleo do protocolo
// ---------------------------------------------------------------------------

pub type AutofillAddressState =
    SingleSlotChannel<AutofillAddressApprovalPayload, AutofillAddressDecision>;

fn address_candidates(entries: &[VaultEntry]) -> Vec<AutofillAddressCandidate> {
    entries
        .iter()
        .filter(|e| e.r#type == EntryType::Address)
        .filter_map(|e| {
            e.address.clone().map(|data| AutofillAddressCandidate {
                entry_id: e.id.clone(),
                data,
            })
        })
        .collect()
}

/// Núcleo do protocolo — lê o Vault local (única dependência de I/O aqui,
/// mesmo motivo de `vault_edit::handle_incoming` chamar `vault::load()`
/// direto) e delega pra `handle_incoming_with_timeout`, que é a parte
/// testável (recebe as entradas já prontas, sem tocar em `$HOME`).
pub async fn handle_incoming(
    state: &AutofillAddressState,
    notify: impl FnOnce(&AutofillAddressApprovalPayload),
) -> AutofillAddressOutcome {
    let entries = match vault::load() {
        Ok(v) => v.entries,
        Err(e) => {
            return AutofillAddressOutcome::Invalid(format!("failed to read local vault: {e}"))
        }
    };
    handle_incoming_with_timeout(state, &entries, notify, AUTOFILL_ADDRESS_REQUEST_TIMEOUT).await
}

async fn handle_incoming_with_timeout(
    state: &AutofillAddressState,
    entries: &[VaultEntry],
    notify: impl FnOnce(&AutofillAddressApprovalPayload),
    timeout: Duration,
) -> AutofillAddressOutcome {
    let candidates = address_candidates(entries);
    if candidates.is_empty() {
        return AutofillAddressOutcome::NoAddresses;
    }

    let (payload, rx) = {
        let payload = AutofillAddressApprovalPayload {
            id: single_slot_channel::random_id(),
            candidates: candidates.clone(),
            expires_at_ms: single_slot_channel::now_ms() + timeout.as_millis() as i64,
        };
        match state.try_park(payload).await {
            Ok(ok) => ok,
            Err(()) => return AutofillAddressOutcome::Busy,
        }
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(AutofillAddressDecision::Approved { entry_id })) => {
            match candidates.into_iter().find(|c| c.entry_id == entry_id) {
                Some(c) => AutofillAddressOutcome::Filled(Box::new(c.data)),
                None => AutofillAddressOutcome::Invalid(
                    "selected entry is not one of the offered candidates".to_string(),
                ),
            }
        }
        Ok(Ok(AutofillAddressDecision::Rejected)) => AutofillAddressOutcome::Rejected,
        Ok(Err(_)) => {
            AutofillAddressOutcome::Invalid("frontend disconnected before responding".to_string())
        }
        Err(_) => {
            state.clear().await;
            AutofillAddressOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_autofill_address_request.
pub async fn current(state: &AutofillAddressState) -> Option<AutofillAddressApprovalPayload> {
    state.current().await
}

/// Usado por respond_to_autofill_address_request.
pub async fn resolve(
    state: &AutofillAddressState,
    id: &str,
    decision: AutofillAddressDecision,
) -> Result<(), String> {
    state.resolve(id, decision).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    // `VaultEntry` tem um campo privado legado (`profile`), inacessível fora
    // de `vault.rs` via struct-literal — construído via `Deserialize` (que
    // não se importa com privacidade de campo, roda dentro do próprio
    // módulo de origem) em vez de tentar reexpor o campo.
    fn entry(id: &str, address: vault::AddressData) -> VaultEntry {
        serde_json::from_value(serde_json::json!({
            "id": id,
            "site": "",
            "url": "",
            "username": "",
            "password": "",
            "notes": "",
            "type": "address",
            "address": address,
            "created_at": 0,
            "updated_at": 0,
        }))
        .expect("valid VaultEntry fixture")
    }

    fn credential_entry(id: &str) -> VaultEntry {
        serde_json::from_value(serde_json::json!({
            "id": id,
            "site": "example.com",
            "url": "",
            "username": "user",
            "password": "hunter2",
            "notes": "",
            "type": "credential",
            "created_at": 0,
            "updated_at": 0,
        }))
        .expect("valid VaultEntry fixture")
    }

    fn sample_address(label: &str) -> vault::AddressData {
        vault::AddressData {
            label: label.to_string(),
            full_name: "Alice Example".to_string(),
            street: "Main St".to_string(),
            number: "123".to_string(),
            complement: None,
            neighborhood: "Downtown".to_string(),
            city: "Springfield".to_string(),
            state: "IL".to_string(),
            zip_code: "00000-000".to_string(),
            country: "US".to_string(),
            phone: None,
        }
    }

    async fn wait_for_pending(state: &AutofillAddressState) -> AutofillAddressApprovalPayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn no_address_entries_returns_no_addresses_without_parking() {
        let state = AutofillAddressState::default();
        let entries = vec![credential_entry("cred")];

        let mut notified = false;
        let outcome = handle_incoming_with_timeout(
            &state,
            &entries,
            |_| notified = true,
            Duration::from_secs(1),
        )
        .await;

        assert!(matches!(outcome, AutofillAddressOutcome::NoAddresses));
        assert!(!notified);
        assert!(current(&state).await.is_none());
    }

    #[tokio::test]
    async fn ignores_non_address_entries_and_offers_only_addresses() {
        let state = Arc::new(AutofillAddressState::default());
        let entries = vec![
            credential_entry("cred"),
            entry("addr1", sample_address("Home")),
        ];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.candidates.len(), 1);
        assert_eq!(payload.candidates[0].entry_id, "addr1");

        resolve(
            &state,
            &payload.id,
            AutofillAddressDecision::Approved {
                entry_id: "addr1".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn approve_returns_filled_with_the_chosen_candidate() {
        let state = Arc::new(AutofillAddressState::default());
        let entries = vec![
            entry("addr1", sample_address("Home")),
            entry("addr2", sample_address("Work")),
        ];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.candidates.len(), 2);

        resolve(
            &state,
            &payload.id,
            AutofillAddressDecision::Approved {
                entry_id: "addr2".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        match outcome {
            AutofillAddressOutcome::Filled(address) => assert_eq!(address.label, "Work"),
            _ => panic!("expected Filled"),
        }
    }

    #[tokio::test]
    async fn reject_returns_rejected() {
        let state = Arc::new(AutofillAddressState::default());
        let entries = vec![entry("addr1", sample_address("Home"))];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, AutofillAddressDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, AutofillAddressOutcome::Rejected));
    }

    #[tokio::test]
    async fn approve_with_unknown_entry_id_is_invalid() {
        let state = Arc::new(AutofillAddressState::default());
        let entries = vec![entry("addr1", sample_address("Home"))];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(
            &state,
            &payload.id,
            AutofillAddressDecision::Approved {
                entry_id: "does-not-exist".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, AutofillAddressOutcome::Invalid(_)));
    }

    #[tokio::test]
    async fn concurrent_second_pending_request_is_busy() {
        let state = Arc::new(AutofillAddressState::default());
        let entries = vec![entry("addr1", sample_address("Home"))];
        let state_bg = state.clone();
        let entries_bg = entries.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries_bg, |_| {}, Duration::from_secs(5))
                .await
        });

        let payload = wait_for_pending(&state).await;

        let second =
            handle_incoming_with_timeout(&state, &entries, |_| {}, Duration::from_secs(5)).await;
        assert!(matches!(second, AutofillAddressOutcome::Busy));

        resolve(&state, &payload.id, AutofillAddressDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_pending_state() {
        let state = AutofillAddressState::default();
        let entries = vec![entry("addr1", sample_address("Home"))];

        let outcome =
            handle_incoming_with_timeout(&state, &entries, |_| {}, Duration::from_millis(50)).await;

        assert!(matches!(outcome, AutofillAddressOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}

use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::single_slot_channel::{self, SingleSlotChannel};
use crate::vault::{self, EntryType, VaultEntry};

/// Tempo que um POST /truthid/v1/autofill-creditcard fica pendurado esperando
/// o usuário escolher/rejeitar — mesmo valor de `autofill_address::
/// AUTOFILL_ADDRESS_REQUEST_TIMEOUT`.
pub const AUTOFILL_CREDITCARD_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

// ---------------------------------------------------------------------------
// Tipos do protocolo HTTP
// ---------------------------------------------------------------------------

/// Um cartão salvo, candidato a preencher o formulário. `entry_id` identifica
/// a entrada do Vault de origem — mesmo papel de `autofill_address::
/// AutofillAddressCandidate::entry_id`.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AutofillCreditCardCandidate {
    pub entry_id: String,
    pub data: vault::CreditCardData,
}

/// O que vai pro evento Tauri e pro comando get_pending_autofill_creditcard_request.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AutofillCreditCardApprovalPayload {
    pub id: String,
    pub candidates: Vec<AutofillCreditCardCandidate>,
    pub expires_at_ms: i64,
}

single_slot_channel::impl_payload_id!(AutofillCreditCardApprovalPayload);

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", tag = "outcome")]
pub enum AutofillCreditCardDecision {
    Approved { entry_id: String },
    Rejected,
}

pub enum AutofillCreditCardOutcome {
    Filled(vault::CreditCardData),
    NoCards,
    Rejected,
    TimedOut,
    Busy,
    Invalid(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AutofillCreditCardResponse {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub card: Option<vault::CreditCardData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl AutofillCreditCardOutcome {
    pub fn into_response(self) -> (axum::http::StatusCode, AutofillCreditCardResponse) {
        use axum::http::StatusCode;
        match self {
            AutofillCreditCardOutcome::Filled(card) => (
                StatusCode::OK,
                AutofillCreditCardResponse {
                    status: "filled",
                    card: Some(card),
                    error: None,
                },
            ),
            AutofillCreditCardOutcome::NoCards => (
                StatusCode::OK,
                AutofillCreditCardResponse {
                    status: "no-cards",
                    card: None,
                    error: None,
                },
            ),
            AutofillCreditCardOutcome::Rejected => (
                StatusCode::FORBIDDEN,
                AutofillCreditCardResponse {
                    status: "rejected",
                    card: None,
                    error: None,
                },
            ),
            AutofillCreditCardOutcome::TimedOut => (
                StatusCode::REQUEST_TIMEOUT,
                AutofillCreditCardResponse {
                    status: "timeout",
                    card: None,
                    error: None,
                },
            ),
            AutofillCreditCardOutcome::Busy => (
                StatusCode::CONFLICT,
                AutofillCreditCardResponse {
                    status: "busy",
                    card: None,
                    error: Some("another autofill request is already pending".to_string()),
                },
            ),
            AutofillCreditCardOutcome::Invalid(error) => (
                StatusCode::BAD_REQUEST,
                AutofillCreditCardResponse {
                    status: "invalid",
                    card: None,
                    error: Some(error),
                },
            ),
        }
    }
}

// ---------------------------------------------------------------------------
// Núcleo do protocolo
// ---------------------------------------------------------------------------

pub type AutofillCreditCardState =
    SingleSlotChannel<AutofillCreditCardApprovalPayload, AutofillCreditCardDecision>;

fn credit_card_candidates(entries: &[VaultEntry]) -> Vec<AutofillCreditCardCandidate> {
    entries
        .iter()
        .filter(|e| e.r#type == EntryType::CreditCard)
        .filter_map(|e| {
            e.credit_card
                .clone()
                .map(|data| AutofillCreditCardCandidate {
                    entry_id: e.id.clone(),
                    data,
                })
        })
        .collect()
}

/// Núcleo do protocolo — mesmo espírito de `autofill_address::handle_incoming`:
/// só a leitura do Vault (`vault::load()`) não é testável diretamente, o resto
/// vive em `handle_incoming_with_timeout`.
pub async fn handle_incoming(
    state: &AutofillCreditCardState,
    notify: impl FnOnce(&AutofillCreditCardApprovalPayload),
) -> AutofillCreditCardOutcome {
    let entries = match vault::load() {
        Ok(v) => v.entries,
        Err(e) => {
            return AutofillCreditCardOutcome::Invalid(format!("failed to read local vault: {e}"))
        }
    };
    handle_incoming_with_timeout(state, &entries, notify, AUTOFILL_CREDITCARD_REQUEST_TIMEOUT).await
}

async fn handle_incoming_with_timeout(
    state: &AutofillCreditCardState,
    entries: &[VaultEntry],
    notify: impl FnOnce(&AutofillCreditCardApprovalPayload),
    timeout: Duration,
) -> AutofillCreditCardOutcome {
    let candidates = credit_card_candidates(entries);
    if candidates.is_empty() {
        return AutofillCreditCardOutcome::NoCards;
    }

    let (payload, rx) = {
        let payload = AutofillCreditCardApprovalPayload {
            id: single_slot_channel::random_id(),
            candidates: candidates.clone(),
            expires_at_ms: single_slot_channel::now_ms() + timeout.as_millis() as i64,
        };
        match state.try_park(payload).await {
            Ok(ok) => ok,
            Err(()) => return AutofillCreditCardOutcome::Busy,
        }
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(AutofillCreditCardDecision::Approved { entry_id })) => {
            match candidates.into_iter().find(|c| c.entry_id == entry_id) {
                Some(c) => AutofillCreditCardOutcome::Filled(c.data),
                None => AutofillCreditCardOutcome::Invalid(
                    "selected entry is not one of the offered candidates".to_string(),
                ),
            }
        }
        Ok(Ok(AutofillCreditCardDecision::Rejected)) => AutofillCreditCardOutcome::Rejected,
        Ok(Err(_)) => AutofillCreditCardOutcome::Invalid(
            "frontend disconnected before responding".to_string(),
        ),
        Err(_) => {
            state.clear().await;
            AutofillCreditCardOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_autofill_creditcard_request.
pub async fn current(state: &AutofillCreditCardState) -> Option<AutofillCreditCardApprovalPayload> {
    state.current().await
}

/// Usado por respond_to_autofill_creditcard_request.
pub async fn resolve(
    state: &AutofillCreditCardState,
    id: &str,
    decision: AutofillCreditCardDecision,
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
    fn entry(id: &str, card: vault::CreditCardData) -> VaultEntry {
        serde_json::from_value(serde_json::json!({
            "id": id,
            "site": "",
            "url": "",
            "username": "",
            "password": "",
            "notes": "",
            "type": "creditCard",
            "credit_card": card,
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

    fn sample_card(label: &str) -> vault::CreditCardData {
        vault::CreditCardData {
            label: label.to_string(),
            card_holder_name: "Alice Example".to_string(),
            card_number: "4111111111111234".to_string(),
            expiry_month: "09".to_string(),
            expiry_year: "2029".to_string(),
            cvv: "123".to_string(),
            bank: None,
            card_network: vault::CardNetwork::Visa,
        }
    }

    async fn wait_for_pending(
        state: &AutofillCreditCardState,
    ) -> AutofillCreditCardApprovalPayload {
        loop {
            if let Some(payload) = current(state).await {
                return payload;
            }
            tokio::task::yield_now().await;
        }
    }

    #[tokio::test]
    async fn no_card_entries_returns_no_cards_without_parking() {
        let state = AutofillCreditCardState::default();
        let entries = vec![credential_entry("cred")];

        let mut notified = false;
        let outcome = handle_incoming_with_timeout(
            &state,
            &entries,
            |_| notified = true,
            Duration::from_secs(1),
        )
        .await;

        assert!(matches!(outcome, AutofillCreditCardOutcome::NoCards));
        assert!(!notified);
        assert!(current(&state).await.is_none());
    }

    #[tokio::test]
    async fn ignores_non_card_entries_and_offers_only_cards() {
        let state = Arc::new(AutofillCreditCardState::default());
        let entries = vec![
            credential_entry("cred"),
            entry("card1", sample_card("Nubank")),
        ];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        assert_eq!(payload.candidates.len(), 1);
        assert_eq!(payload.candidates[0].entry_id, "card1");

        resolve(
            &state,
            &payload.id,
            AutofillCreditCardDecision::Approved {
                entry_id: "card1".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn approve_returns_filled_with_the_chosen_candidate() {
        let state = Arc::new(AutofillCreditCardState::default());
        let entries = vec![
            entry("card1", sample_card("Nubank")),
            entry("card2", sample_card("Itau Platinum")),
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
            AutofillCreditCardDecision::Approved {
                entry_id: "card2".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        match outcome {
            AutofillCreditCardOutcome::Filled(card) => assert_eq!(card.label, "Itau Platinum"),
            _ => panic!("expected Filled"),
        }
    }

    #[tokio::test]
    async fn reject_returns_rejected() {
        let state = Arc::new(AutofillCreditCardState::default());
        let entries = vec![entry("card1", sample_card("Nubank"))];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(&state, &payload.id, AutofillCreditCardDecision::Rejected)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, AutofillCreditCardOutcome::Rejected));
    }

    #[tokio::test]
    async fn approve_with_unknown_entry_id_is_invalid() {
        let state = Arc::new(AutofillCreditCardState::default());
        let entries = vec![entry("card1", sample_card("Nubank"))];
        let state_bg = state.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries, |_| {}, Duration::from_secs(5)).await
        });

        let payload = wait_for_pending(&state).await;
        resolve(
            &state,
            &payload.id,
            AutofillCreditCardDecision::Approved {
                entry_id: "does-not-exist".to_string(),
            },
        )
        .await
        .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, AutofillCreditCardOutcome::Invalid(_)));
    }

    #[tokio::test]
    async fn concurrent_second_pending_request_is_busy() {
        let state = Arc::new(AutofillCreditCardState::default());
        let entries = vec![entry("card1", sample_card("Nubank"))];
        let state_bg = state.clone();
        let entries_bg = entries.clone();
        let handle = tokio::spawn(async move {
            handle_incoming_with_timeout(&state_bg, &entries_bg, |_| {}, Duration::from_secs(5))
                .await
        });

        let payload = wait_for_pending(&state).await;

        let second =
            handle_incoming_with_timeout(&state, &entries, |_| {}, Duration::from_secs(5)).await;
        assert!(matches!(second, AutofillCreditCardOutcome::Busy));

        resolve(&state, &payload.id, AutofillCreditCardDecision::Rejected)
            .await
            .expect("resolve should succeed");
        handle.await.expect("task should not panic");
    }

    #[tokio::test]
    async fn timeout_returns_timed_out_and_clears_pending_state() {
        let state = AutofillCreditCardState::default();
        let entries = vec![entry("card1", sample_card("Nubank"))];

        let outcome =
            handle_incoming_with_timeout(&state, &entries, |_| {}, Duration::from_millis(50)).await;

        assert!(matches!(outcome, AutofillCreditCardOutcome::TimedOut));
        assert!(current(&state).await.is_none());
    }
}

use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rand::RngCore;
use serde::{Deserialize, Serialize};
use tokio::sync::{oneshot, Mutex};

/// Tempo que um POST /truthid/v1/pin fica pendurado esperando o usuário
/// aprovar/rejeitar antes de devolver 408 — só no caminho de aprovação (app
/// novo ou cota estourada). O caminho autorizado+dentro-da-cota nunca pausa.
pub const PIN_REQUEST_TIMEOUT: Duration = Duration::from_secs(300);

/// Cota diária sugerida na primeira autorização de um app. Editar esse valor
/// por app fica pra uma fatia futura (tela de Settings) — por ora é fixo,
/// suficiente pra cobrir uso normal (ex: salvar a cada edição) sem abrir
/// espaço pra um app com bug/malicioso esgotar a cota dos providers do
/// usuário em silêncio.
const DEFAULT_DAILY_LIMIT: u32 = 50;

/// Janela rolante de 24h a partir do primeiro uso do dia — não é meia-noite
/// de fuso nenhum, deliberadamente, pra não depender de timezone local.
const DAY_MS: i64 = 24 * 60 * 60 * 1000;

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

#[derive(Serialize, Clone, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum PinApprovalReason {
    /// Primeira vez que este app pede pra pinar algo.
    NewApp,
    /// App já autorizado, mas bateu no limite diário.
    QuotaExceeded,
}

/// O que vai pro evento Tauri e pro comando get_pending_pin_request — tudo
/// que o frontend precisa pra renderizar a tela de aprovação. Não inclui o
/// conteúdo em si (o TruthID nunca precisa mostrar/inspecionar o blob
/// cifrado pra decidir se autoriza o app a usar o pinning).
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PinApprovalPayload {
    pub id: String,
    pub app_name: String,
    pub reason: PinApprovalReason,
    pub daily_limit: u32,
    pub expires_at_ms: i64,
}

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
// Autorizações por app (persistidas)
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
struct PinAuthorization {
    app_name: String,
    daily_limit: u32,
    used_today: u32,
    day_start_ms: i64,
}

fn default_authorizations_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    std::path::Path::new(&home)
        .join(".truthid")
        .join("pin_authorizations.json")
}

fn load_authorizations(path: &std::path::Path) -> Vec<PinAuthorization> {
    if !path.exists() {
        return Vec::new();
    }
    let raw = std::fs::read_to_string(path).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

fn save_authorizations(
    path: &std::path::Path,
    authorizations: &[PinAuthorization],
) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(authorizations).map_err(|e| e.to_string())?;
    std::fs::write(path, json).map_err(|e| e.to_string())
}

/// Se já passou um dia inteiro desde o início da janela atual, zera a cota.
fn reset_if_new_day(auth: &mut PinAuthorization, now: i64) {
    if now - auth.day_start_ms >= DAY_MS {
        auth.used_today = 0;
        auth.day_start_ms = now;
    }
}

// ---------------------------------------------------------------------------
// Núcleo do protocolo
// ---------------------------------------------------------------------------

struct PendingPin {
    payload: PinApprovalPayload,
    responder: oneshot::Sender<PinDecision>,
}

/// tokio::sync::Mutex (não std): os guards atravessam .await tanto em
/// handle_incoming (espera o oneshot) quanto no caminho autorizado (grava o
/// arquivo de autorizações). `pending` e `quota` são locks separados —
/// consumir cota no caminho rápido (autorizado) não precisa disputar com o
/// slot de aprovação pendente, e vice-versa. `authorizations_path` é
/// injetado (não lido de $HOME direto) pra este módulo ser testável sem
/// mexer em estado global — `cargo test` roda em paralelo e vários outros
/// módulos deste crate (vault.rs, ipfs.rs, bundler.rs) também leem
/// $HOME/.truthid/... durante os próprios testes.
pub struct PinState {
    pending: Mutex<Option<PendingPin>>,
    quota: Mutex<()>,
    authorizations_path: PathBuf,
}

impl Default for PinState {
    fn default() -> Self {
        Self {
            pending: Mutex::new(None),
            quota: Mutex::new(()),
            authorizations_path: default_authorizations_path(),
        }
    }
}

#[cfg(test)]
impl PinState {
    /// pub(crate) (não privado): também usado pelos testes de
    /// local_signer_server.rs, que precisam da mesma isolação de arquivo
    /// (ver o comentário em `temp_authorizations_path`, no módulo de testes
    /// abaixo, sobre por que isso não pode ser $HOME global).
    pub(crate) fn with_authorizations_path(path: PathBuf) -> Self {
        Self {
            pending: Mutex::new(None),
            quota: Mutex::new(()),
            authorizations_path: path,
        }
    }
}

/// Tenta consumir 1 unidade de cota do app, se autorizado. `Some(true)` =
/// consumiu, pode pinar direto. `Some(false)` = autorizado mas sem cota
/// sobrando (precisa aprovação). `None` = app nunca autorizado (precisa
/// aprovação). Grava o arquivo de autorizações sempre que altera algo.
async fn try_consume_quota(state: &PinState, app_name: &str) -> Result<Option<bool>, String> {
    let _guard = state.quota.lock().await;
    let mut authorizations = load_authorizations(&state.authorizations_path);
    let now = now_ms();

    let Some(auth) = authorizations.iter_mut().find(|a| a.app_name == app_name) else {
        return Ok(None);
    };

    reset_if_new_day(auth, now);
    if auth.used_today >= auth.daily_limit {
        return Ok(Some(false));
    }

    auth.used_today += 1;
    save_authorizations(&state.authorizations_path, &authorizations)?;
    Ok(Some(true))
}

/// Chamado só depois de uma aprovação (app novo ou reset de cota). App novo:
/// cria a autorização do zero. Cota estourada: reseta a janela a partir de
/// agora, mantendo o mesmo daily_limit — ajustar o limite em si fica pra uma
/// tela de Settings futura, aprovar aqui só desbloqueia o dia.
async fn record_approval(
    state: &PinState,
    app_name: &str,
    reason: &PinApprovalReason,
) -> Result<(), String> {
    let _guard = state.quota.lock().await;
    let mut authorizations = load_authorizations(&state.authorizations_path);
    let now = now_ms();

    match authorizations.iter_mut().find(|a| a.app_name == app_name) {
        Some(auth) if *reason == PinApprovalReason::QuotaExceeded => {
            auth.used_today = 1;
            auth.day_start_ms = now;
        }
        _ => {
            authorizations.retain(|a| a.app_name != app_name);
            authorizations.push(PinAuthorization {
                app_name: app_name.to_string(),
                daily_limit: DEFAULT_DAILY_LIMIT,
                used_today: 1,
                day_start_ms: now,
            });
        }
    }

    save_authorizations(&state.authorizations_path, &authorizations)
}

/// Núcleo do protocolo — sem dependência de tauri::AppHandle, mesmo espírito
/// de sign_message::handle_incoming. `notify` só é chamado quando este
/// pedido específico precisa de aprovação humana (app novo ou cota
/// estourada); no caminho rápido (autorizado, dentro da cota) nunca é
/// chamado. `pin` é injetado pra este módulo ser testável sem HTTP real — é
/// assíncrono (não `FnOnce` síncrono como o `sign` de sign_message.rs)
/// porque `ipfs::pin_vault`, a implementação real, faz chamadas HTTP.
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

    let reason = match try_consume_quota(state, &app_name).await {
        Ok(Some(true)) => None, // já consumiu, pina direto
        Ok(Some(false)) => Some(PinApprovalReason::QuotaExceeded),
        Ok(None) => Some(PinApprovalReason::NewApp),
        Err(e) => return PinOutcome::Failed(e),
    };

    let Some(reason) = reason else {
        return match pin(content).await {
            Ok((cid, content_hash, providers_ok, providers_failed)) => PinOutcome::Pinned {
                cid,
                content_hash,
                providers_ok,
                providers_failed,
            },
            Err(e) => PinOutcome::Failed(e),
        };
    };

    let (payload, rx) = {
        let mut guard = state.pending.lock().await;
        if guard.is_some() {
            return PinOutcome::Busy;
        }

        let payload = PinApprovalPayload {
            id: random_id(),
            app_name: app_name.clone(),
            reason,
            daily_limit: DEFAULT_DAILY_LIMIT,
            expires_at_ms: now_ms() + timeout.as_millis() as i64,
        };
        let (tx, rx) = oneshot::channel();
        *guard = Some(PendingPin {
            payload: payload.clone(),
            responder: tx,
        });
        (payload, rx)
    };

    notify(&payload);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(PinDecision::Approved)) => {
            if let Err(e) = record_approval(state, &app_name, &payload.reason).await {
                return PinOutcome::Failed(e);
            }
            match pin(content).await {
                Ok((cid, content_hash, providers_ok, providers_failed)) => PinOutcome::Pinned {
                    cid,
                    content_hash,
                    providers_ok,
                    providers_failed,
                },
                Err(e) => PinOutcome::Failed(e),
            }
        }
        Ok(Ok(PinDecision::Rejected)) => PinOutcome::Rejected,
        Ok(Err(_)) => PinOutcome::Failed("frontend disconnected before responding".to_string()),
        Err(_) => {
            state.pending.lock().await.take();
            PinOutcome::TimedOut
        }
    }
}

/// Usado por get_pending_pin_request.
pub async fn current(state: &PinState) -> Option<PinApprovalPayload> {
    state
        .pending
        .lock()
        .await
        .as_ref()
        .map(|p| p.payload.clone())
}

/// Usado por respond_to_pin_request, depois do usuário aprovar/rejeitar.
pub async fn resolve(state: &PinState, id: &str, decision: PinDecision) -> Result<(), String> {
    let mut guard = state.pending.lock().await;
    match guard.take() {
        Some(pending) if pending.payload.id == id => {
            let _ = pending.responder.send(decision);
            Ok(())
        }
        Some(pending) => {
            *guard = Some(pending);
            Err("id does not match the currently pending pin request".to_string())
        }
        None => Err("no pending pin request (it may have already expired)".to_string()),
    }
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
            vec!["kubo-local".to_string()],
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

    /// Caminho de arquivo único por teste (não $HOME global) — cargo test roda
    /// em paralelo, e vários outros módulos deste crate (vault.rs, ipfs.rs,
    /// bundler.rs) também leem $HOME/.truthid/... durante os próprios testes;
    /// mexer em $HOME de verdade seria uma fonte real de flakiness cruzada
    /// entre módulos. `PinState::with_authorizations_path` (test-only) injeta
    /// esse caminho em vez de deixar o módulo resolver $HOME sozinho.
    fn temp_authorizations_path() -> PathBuf {
        std::env::temp_dir().join(format!("truthid-pin-test-{}.json", random_id()))
    }

    #[tokio::test]
    async fn new_app_parks_for_approval_then_pins_on_approve() {
        let path = temp_authorizations_path();
        let state = Arc::new(PinState::with_authorizations_path(path.clone()));
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
        assert_eq!(payload.reason, PinApprovalReason::NewApp);
        assert_eq!(payload.daily_limit, DEFAULT_DAILY_LIMIT);

        resolve(&state, &payload.id, PinDecision::Approved)
            .await
            .expect("resolve should succeed");

        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, PinOutcome::Pinned { .. }));

        let authorizations = load_authorizations(&path);
        assert_eq!(authorizations.len(), 1);
        assert_eq!(authorizations[0].used_today, 1);
        assert_eq!(authorizations[0].daily_limit, DEFAULT_DAILY_LIMIT);
    }

    #[tokio::test]
    async fn rejected_new_app_never_calls_pin_and_never_persists() {
        let path = temp_authorizations_path();
        let state = Arc::new(PinState::with_authorizations_path(path.clone()));
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
        assert!(load_authorizations(&path).is_empty());
    }

    #[tokio::test]
    async fn authorized_app_within_quota_pins_without_parking() {
        let path = temp_authorizations_path();
        save_authorizations(
            &path,
            &[PinAuthorization {
                app_name: "Practice Valuation".to_string(),
                daily_limit: 50,
                used_today: 3,
                day_start_ms: now_ms(),
            }],
        )
        .expect("save");

        let state = PinState::with_authorizations_path(path.clone());
        let mut notified = false;
        let outcome = handle_incoming(
            &state,
            body("Practice Valuation", b"hello"),
            |_| notified = true,
            fake_pin,
        )
        .await;

        assert!(
            !notified,
            "authorized app within quota must not trigger an approval popup"
        );
        assert!(matches!(outcome, PinOutcome::Pinned { .. }));

        let authorizations = load_authorizations(&path);
        assert_eq!(authorizations[0].used_today, 4);
    }

    #[tokio::test]
    async fn quota_exceeded_parks_and_reset_on_approve() {
        let path = temp_authorizations_path();
        save_authorizations(
            &path,
            &[PinAuthorization {
                app_name: "Practice Valuation".to_string(),
                daily_limit: 2,
                used_today: 2,
                day_start_ms: now_ms(),
            }],
        )
        .expect("save");

        let state = Arc::new(PinState::with_authorizations_path(path.clone()));
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
        assert_eq!(payload.reason, PinApprovalReason::QuotaExceeded);

        resolve(&state, &payload.id, PinDecision::Approved)
            .await
            .expect("resolve should succeed");
        let outcome = handle.await.expect("task should not panic");
        assert!(matches!(outcome, PinOutcome::Pinned { .. }));

        let authorizations = load_authorizations(&path);
        assert_eq!(authorizations[0].used_today, 1);
        assert_eq!(
            authorizations[0].daily_limit, 2,
            "approving a quota reset keeps the same limit"
        );
    }

    #[tokio::test]
    async fn quota_resets_after_a_full_day() {
        let path = temp_authorizations_path();
        save_authorizations(
            &path,
            &[PinAuthorization {
                app_name: "Practice Valuation".to_string(),
                daily_limit: 1,
                used_today: 1,
                day_start_ms: now_ms() - DAY_MS - 1,
            }],
        )
        .expect("save");

        let state = PinState::with_authorizations_path(path);
        let mut notified = false;
        let outcome = handle_incoming(
            &state,
            body("Practice Valuation", b"hello"),
            |_| notified = true,
            fake_pin,
        )
        .await;

        assert!(!notified, "a fresh day should not require re-approval");
        assert!(matches!(outcome, PinOutcome::Pinned { .. }));
    }

    #[tokio::test]
    async fn concurrent_second_pending_request_is_busy() {
        let path = temp_authorizations_path();
        let state = Arc::new(PinState::with_authorizations_path(path));
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
        let state = PinState::with_authorizations_path(temp_authorizations_path());

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
        let path = temp_authorizations_path();
        let state = PinState::with_authorizations_path(path.clone());

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
        // Timeout não deve consumir/gravar cota nenhuma — o app segue "novo".
        assert!(load_authorizations(&path).is_empty());
    }
}

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;

use axum::{extract::Json, extract::State, http::StatusCode, routing::get, routing::post, Router};
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio::sync::{oneshot, Mutex};

use crate::pin::{self, PinState};
use crate::sign_message::{self, SignMessageState};
use crate::sign_request::{self, SignRequestState};
use crate::vault_edit::{self, VaultEditState};

/// Callback chamado sempre que um /sign-request novo chega, pra quem estiver
/// rodando o servidor decidir como notificar a UI (normalmente app.emit do
/// Tauri). Injetado como closure (não um tauri::AppHandle direto) pra manter
/// este módulo e o sign_request.rs testáveis sem precisar de um app Tauri de
/// verdade rodando.
type SignRequestNotifier = Arc<dyn Fn(&sign_request::SignRequestPayload) + Send + Sync>;

/// Mesma ideia de SignRequestNotifier, só que pro canal /sign-message.
type SignMessageNotifier = Arc<dyn Fn(&sign_message::SignMessagePayload) + Send + Sync>;

/// Mesma ideia de SignRequestNotifier, só que pro canal /pin.
type PinNotifier = Arc<dyn Fn(&pin::PinApprovalPayload) + Send + Sync>;

/// Mesma ideia de SignRequestNotifier, só que pro canal /vault-edit.
type VaultEditNotifier = Arc<dyn Fn(&vault_edit::VaultEditApprovalPayload) + Send + Sync>;

#[derive(Clone)]
struct SignRequestRouterState {
    sign_requests: Arc<SignRequestState>,
    on_sign_request: SignRequestNotifier,
    sign_messages: Arc<SignMessageState>,
    on_sign_message: SignMessageNotifier,
    pin_requests: Arc<PinState>,
    on_pin_request: PinNotifier,
    vault_edit_requests: Arc<VaultEditState>,
    on_vault_edit_request: VaultEditNotifier,
}

/// Portas candidatas para o canal local Desktop<->app terceiro. Bloco próprio,
/// distinto de 47850..47854 (LAN do Mobile/extensão, Fase 13.9) e de 1420
/// (Vite dev server). Precisa ser espelhado manualmente do lado do app
/// terceiro (ex: Practice Valuation) quando essa integração acontecer.
pub const CANDIDATE_PORTS: [u16; 5] = [47950, 47951, 47952, 47953, 47954];

struct RunningServer {
    port: u16,
    shutdown_tx: oneshot::Sender<()>,
    join_handle: tauri::async_runtime::JoinHandle<()>,
}

/// tokio::sync::Mutex, não std::sync::Mutex: o guard atravessa pontos de
/// .await em start()/stop() (esperar o socket ser liberado no stop, esperar
/// o bind no start).
#[derive(Default)]
pub struct LocalSignerServerState(Mutex<Option<RunningServer>>);

#[derive(Serialize, Clone)]
pub struct LocalSignerStatus {
    pub running: bool,
    pub port: Option<u16>,
}

#[derive(Serialize)]
struct PingResponse {
    service: &'static str,
    version: &'static str,
    status: &'static str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct HandshakeRequest {
    #[serde(default)]
    app_name: String,
    #[serde(default)]
    app_version: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HandshakeResponse {
    accepted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    service: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    desktop_version: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'static str>,
}

async fn ping() -> Json<PingResponse> {
    Json(PingResponse {
        service: "truthid-desktop",
        version: env!("CARGO_PKG_VERSION"),
        status: "ready",
    })
}

// app_version não é usado na resposta (ainda não há nada pra decidir com base
// nela nesta fatia) — só validamos appName, que é o único campo que a 2b vai
// precisar pra exibir "App X quer se conectar" numa futura tela de aprovação.
async fn handshake(
    Json(payload): Json<HandshakeRequest>,
) -> (StatusCode, Json<HandshakeResponse>) {
    let _ = &payload.app_version;
    if payload.app_name.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(HandshakeResponse {
                accepted: false,
                service: None,
                desktop_version: None,
                error: Some("appName is required"),
            }),
        );
    }

    (
        StatusCode::OK,
        Json(HandshakeResponse {
            accepted: true,
            service: Some("truthid-desktop"),
            desktop_version: Some(env!("CARGO_PKG_VERSION")),
            error: None,
        }),
    )
}

async fn sign_request_handler(
    State(router_state): State<SignRequestRouterState>,
    Json(body): Json<sign_request::SignRequestBody>,
) -> (StatusCode, Json<sign_request::SignRequestResponse>) {
    // Best-effort: se não houver nenhuma janela ouvindo agora, o frontend
    // ainda consegue pegar o pedido via get_pending_sign_request ao montar
    // (ver useIncomingSignRequest.ts).
    let outcome = sign_request::handle_incoming(&router_state.sign_requests, body, |payload| {
        (router_state.on_sign_request)(payload);
    })
    .await;
    let (status, body) = outcome.into_response();
    (status, Json(body))
}

async fn sign_message_handler(
    State(router_state): State<SignRequestRouterState>,
    Json(body): Json<sign_message::SignMessageBody>,
) -> (StatusCode, Json<sign_message::SignMessageResponse>) {
    let outcome = sign_message::handle_incoming(
        &router_state.sign_messages,
        body,
        |payload| (router_state.on_sign_message)(payload),
        crate::sign_personal_message,
    )
    .await;
    let (status, body) = outcome.into_response();
    (status, Json(body))
}

async fn pin_handler(
    State(router_state): State<SignRequestRouterState>,
    Json(body): Json<pin::PinRequestBody>,
) -> (StatusCode, Json<pin::PinResponse>) {
    let outcome = pin::handle_incoming(
        &router_state.pin_requests,
        body,
        |payload| (router_state.on_pin_request)(payload),
        crate::pin_content,
    )
    .await;
    let (status, body) = outcome.into_response();
    (status, Json(body))
}

async fn vault_edit_handler(
    State(router_state): State<SignRequestRouterState>,
    Json(body): Json<vault_edit::VaultEditRequestBody>,
) -> (StatusCode, Json<vault_edit::VaultEditResponse>) {
    let outcome = vault_edit::handle_incoming(&router_state.vault_edit_requests, body, |payload| {
        (router_state.on_vault_edit_request)(payload)
    })
    .await;
    let (status, body) = outcome.into_response();
    (status, Json(body))
}

fn router(router_state: SignRequestRouterState) -> Router {
    Router::new()
        .route("/truthid/v1/ping", get(ping))
        .route("/truthid/v1/handshake", post(handshake))
        .route("/truthid/v1/sign-request", post(sign_request_handler))
        .route("/truthid/v1/sign-message", post(sign_message_handler))
        .route("/truthid/v1/pin", post(pin_handler))
        .route("/truthid/v1/vault-edit", post(vault_edit_handler))
        .with_state(router_state)
}

/// Sobe o servidor na primeira porta livre de CANDIDATE_PORTS, bindada em
/// 127.0.0.1 (nunca 0.0.0.0 — os dois processos estão sempre na mesma
/// máquina, então loopback já é suficiente e é bem mais seguro). Idempotente:
/// se já estiver rodando, devolve o status atual sem religar.
///
/// `sign_requests` é o mesmo SignRequestState gerenciado pelo Tauri (pra
/// get_pending_sign_request/respond_to_sign_request enxergarem os mesmos
/// pedidos que chegam via HTTP); `on_sign_request` é chamado sempre que um
/// pedido novo chega (normalmente app.emit, injetado por quem chama start()).
/// `sign_messages`/`on_sign_message` são o equivalente pro canal
/// /truthid/v1/sign-message; `pin_requests`/`on_pin_request`, pro /truthid/v1/pin;
/// `vault_edit_requests`/`on_vault_edit_request`, pro /truthid/v1/vault-edit.
pub async fn start(
    state: &LocalSignerServerState,
    sign_requests: Arc<SignRequestState>,
    on_sign_request: impl Fn(&sign_request::SignRequestPayload) + Send + Sync + 'static,
    sign_messages: Arc<SignMessageState>,
    on_sign_message: impl Fn(&sign_message::SignMessagePayload) + Send + Sync + 'static,
    pin_requests: Arc<PinState>,
    on_pin_request: impl Fn(&pin::PinApprovalPayload) + Send + Sync + 'static,
    vault_edit_requests: Arc<VaultEditState>,
    on_vault_edit_request: impl Fn(&vault_edit::VaultEditApprovalPayload) + Send + Sync + 'static,
) -> Result<LocalSignerStatus, String> {
    let mut guard = state.0.lock().await;
    if let Some(running) = guard.as_ref() {
        return Ok(LocalSignerStatus {
            running: true,
            port: Some(running.port),
        });
    }

    let mut bound = None;
    for port in CANDIDATE_PORTS {
        let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
        if let Ok(listener) = TcpListener::bind(addr).await {
            bound = Some((listener, port));
            break;
        }
    }
    let (listener, port) =
        bound.ok_or_else(|| "no candidate port available for local signer server".to_string())?;

    let router_state = SignRequestRouterState {
        sign_requests,
        on_sign_request: Arc::new(on_sign_request),
        sign_messages,
        on_sign_message: Arc::new(on_sign_message),
        pin_requests,
        on_pin_request: Arc::new(on_pin_request),
        vault_edit_requests,
        on_vault_edit_request: Arc::new(on_vault_edit_request),
    };

    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let join_handle = tauri::async_runtime::spawn(async move {
        let _ = axum::serve(listener, router(router_state))
            .with_graceful_shutdown(async {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    *guard = Some(RunningServer {
        port,
        shutdown_tx,
        join_handle,
    });

    Ok(LocalSignerStatus {
        running: true,
        port: Some(port),
    })
}

/// Pede o graceful shutdown e espera o socket ser liberado antes de
/// devolver — sem esse .await, um start() logo em seguida poderia tentar
/// religar na mesma porta antes do SO soltá-la.
///
/// Se um request estiver estacionado aguardando aprovação (até 300s),
/// o graceful shutdown pode demorar. Timeout de 5s: se o servidor não
/// parar nesse período, aborta a task e libera o botão na UI.
pub async fn stop(state: &LocalSignerServerState) -> LocalSignerStatus {
    let mut guard = state.0.lock().await;
    if let Some(running) = guard.take() {
        let _ = running.shutdown_tx.send(());
        // Timeout de 5s no graceful shutdown: se um request estacionado
        // (até 300s) impede a parada, o JoinHandle é dropado e a task
        // abortada automaticamente — a UI não fica congelada.
        if tokio::time::timeout(Duration::from_secs(5), running.join_handle)
            .await
            .is_err()
        {
            // Timeout: server task foi dropada/abortada.
        }
    }
    LocalSignerStatus {
        running: false,
        port: None,
    }
}

pub async fn status(state: &LocalSignerServerState) -> LocalSignerStatus {
    let guard = state.0.lock().await;
    match guard.as_ref() {
        Some(running) => LocalSignerStatus {
            running: true,
            port: Some(running.port),
        },
        None => LocalSignerStatus {
            running: false,
            port: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // cargo test roda os testes de um mesmo binário em paralelo por padrão.
    // Como CANDIDATE_PORTS é uma lista finita compartilhada por processo
    // (todo teste bate no loopback real, não num mock), 6 testes soltos ao
    // mesmo tempo esgotam as 5 portas e um deles falha "no candidate port
    // available" de forma instável. Esse lock serializa o ciclo de vida
    // completo (start..stop) de cada teste, então nunca há mais de 1 porta
    // em uso por vez — não é sobre corrigir uma race no bind em si.
    static PORT_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    fn base_url(status: &LocalSignerStatus) -> String {
        format!("http://127.0.0.1:{}", status.port.expect("port set while running"))
    }

    // Caminho de arquivo único por teste (não $HOME global) pro estado do
    // pin::PinState — mesmo motivo do helper equivalente em pin.rs::tests:
    // cargo test roda em paralelo, e mexer em $HOME de verdade contaminaria
    // outros módulos deste crate que também leem $HOME/.truthid/... nos
    // próprios testes.
    fn temp_pin_state() -> Arc<PinState> {
        Arc::new(PinState::with_authorizations_path(
            std::env::temp_dir().join(format!(
                "truthid-lss-pin-test-{}.json",
                rand::random::<u64>()
            )),
        ))
    }

    // VaultEditState não tem arquivo nenhum (tudo em memória) — sem
    // isolamento de caminho pra fazer, ao contrário de temp_pin_state acima.
    fn temp_vault_edit_state() -> Arc<VaultEditState> {
        Arc::new(VaultEditState::default())
    }

    // Testes que só exercitam ping/handshake não se importam com o
    // sign_request::SignRequestState nem com notificação — esse helper
    // isola esse boilerplate.
    async fn start_for_test(state: &LocalSignerServerState) -> Result<LocalSignerStatus, String> {
        start(
            state,
            Arc::new(SignRequestState::default()),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            temp_pin_state(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
    }

    #[tokio::test]
    async fn start_binds_to_a_candidate_port_and_status_reflects_it() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();

        let started = start_for_test(&state).await.expect("start should succeed");
        assert!(started.running);
        assert!(CANDIDATE_PORTS.contains(&started.port.expect("port set")));

        let current = status(&state).await;
        assert_eq!(current.port, started.port);

        stop(&state).await;
    }

    #[tokio::test]
    async fn ping_endpoint_returns_expected_service_identifier() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let started = start_for_test(&state).await.expect("start should succeed");

        let resp = reqwest::get(format!("{}/truthid/v1/ping", base_url(&started)))
            .await
            .expect("request should succeed");
        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["service"], "truthid-desktop");
        assert_eq!(body["status"], "ready");

        stop(&state).await;
    }

    #[tokio::test]
    async fn handshake_endpoint_accepts_valid_payload() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let started = start_for_test(&state).await.expect("start should succeed");

        let resp = reqwest::Client::new()
            .post(format!("{}/truthid/v1/handshake", base_url(&started)))
            .json(&serde_json::json!({ "appName": "Practice Valuation", "appVersion": "0.4.0" }))
            .send()
            .await
            .expect("request should succeed");
        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["accepted"], true);
        assert_eq!(body["service"], "truthid-desktop");

        stop(&state).await;
    }

    #[tokio::test]
    async fn handshake_endpoint_rejects_missing_app_name() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let started = start_for_test(&state).await.expect("start should succeed");

        let resp = reqwest::Client::new()
            .post(format!("{}/truthid/v1/handshake", base_url(&started)))
            .json(&serde_json::json!({ "appName": "" }))
            .send()
            .await
            .expect("request should succeed");
        assert_eq!(resp.status(), 400);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["accepted"], false);

        stop(&state).await;
    }

    #[tokio::test]
    async fn unknown_path_returns_404() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let started = start_for_test(&state).await.expect("start should succeed");

        let resp = reqwest::get(format!("{}/truthid/v1/nope", base_url(&started)))
            .await
            .expect("request should succeed");
        assert_eq!(resp.status(), 404);

        stop(&state).await;
    }

    #[tokio::test]
    async fn stop_then_start_reuses_port_without_leaking_it() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();

        let first = start_for_test(&state).await.expect("first start should succeed");
        stop(&state).await;

        let second = start_for_test(&state).await.expect("second start should succeed");
        assert_eq!(first.port, second.port);

        let resp = reqwest::get(format!("{}/truthid/v1/ping", base_url(&second)))
            .await
            .expect("server should respond after restart");
        assert_eq!(resp.status(), 200);

        stop(&state).await;
    }

    #[tokio::test]
    async fn sign_request_endpoint_parks_until_resolved() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let sign_requests = Arc::new(SignRequestState::default());
        let started = start(
            &state,
            sign_requests.clone(),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            temp_pin_state(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/sign-request", base_url(&started));
        let request = reqwest::Client::new().post(&url).json(&serde_json::json!({
            "appName": "Practice Valuation",
            "dest": "0x0000000000000000000000000000000000000001",
            "value": "0",
            "callData": "0xa9059cbb",
            "functionSignature": "transfer(address,uint256)",
        }));

        let (resp, _) = tokio::join!(request.send(), async {
            // Espera o pedido aparecer no state compartilhado, então resolve
            // como se o usuário tivesse aprovado na UI.
            let id = loop {
                if let Some(payload) = sign_request::current(&sign_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            sign_request::resolve(
                &sign_requests,
                &id,
                sign_request::SignRequestDecision::Rejected,
            )
            .await
            .expect("resolve should succeed");
        });

        let resp = resp.expect("request should succeed");
        assert_eq!(resp.status(), 403);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["status"], "rejected");

        stop(&state).await;
    }

    #[tokio::test]
    async fn sign_request_endpoint_rejects_concurrent_second_request() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let sign_requests = Arc::new(SignRequestState::default());
        let started = start(
            &state,
            sign_requests.clone(),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            temp_pin_state(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/sign-request", base_url(&started));
        let body = serde_json::json!({
            "appName": "Practice Valuation",
            "dest": "0x0000000000000000000000000000000000000001",
            "value": "0",
            "callData": "0xa9059cbb",
            "functionSignature": "transfer(address,uint256)",
        });

        let first_request = reqwest::Client::new().post(&url).json(&body).send();
        let second_request = async {
            let id = loop {
                if let Some(payload) = sign_request::current(&sign_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            let resp = reqwest::Client::new().post(&url).json(&body).send().await;
            sign_request::resolve(
                &sign_requests,
                &id,
                sign_request::SignRequestDecision::Rejected,
            )
            .await
            .expect("resolve should succeed");
            resp
        };

        let (first, second) = tokio::join!(first_request, second_request);
        assert_eq!(second.expect("request should succeed").status(), 409);
        assert_eq!(first.expect("request should succeed").status(), 403);

        stop(&state).await;
    }

    #[tokio::test]
    async fn sign_message_endpoint_parks_until_resolved_and_returns_signature() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let sign_messages = Arc::new(SignMessageState::default());
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            sign_messages.clone(),
            |_| {},
            temp_pin_state(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/sign-message", base_url(&started));
        let request = reqwest::Client::new().post(&url).json(&serde_json::json!({
            "appName": "Practice Valuation",
            "purpose": "vault-sync-key",
        }));

        let (resp, _) = tokio::join!(request.send(), async {
            let id = loop {
                if let Some(payload) = sign_message::current(&sign_messages).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            sign_message::resolve(&sign_messages, &id, sign_message::SignMessageDecision::Approved)
                .await
                .expect("resolve should succeed");
        });

        let resp = resp.expect("request should succeed");
        assert_eq!(resp.status(), 200);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["status"], "signed");
        assert_eq!(body["message"], "TruthID Message Signing: Practice Valuation:vault-sync-key");
        assert!(body["signature"].as_str().is_some_and(|s| s.starts_with("0x")));

        stop(&state).await;
    }

    #[tokio::test]
    async fn sign_message_endpoint_rejects_concurrent_second_request() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let sign_messages = Arc::new(SignMessageState::default());
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            sign_messages.clone(),
            |_| {},
            temp_pin_state(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/sign-message", base_url(&started));
        let body = serde_json::json!({
            "appName": "Practice Valuation",
            "purpose": "vault-sync-key",
        });

        let first_request = reqwest::Client::new().post(&url).json(&body).send();
        let second_request = async {
            let id = loop {
                if let Some(payload) = sign_message::current(&sign_messages).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            let resp = reqwest::Client::new().post(&url).json(&body).send().await;
            sign_message::resolve(&sign_messages, &id, sign_message::SignMessageDecision::Rejected)
                .await
                .expect("resolve should succeed");
            resp
        };

        let (first, second) = tokio::join!(first_request, second_request);
        assert_eq!(second.expect("request should succeed").status(), 409);
        assert_eq!(first.expect("request should succeed").status(), 403);

        stop(&state).await;
    }

    // Os 2 testes de /pin abaixo só exercitam o caminho Rejected — ao
    // contrário de sign-message, o `pin` real (crate::pin_content) faz
    // chamadas HTTP de verdade pros providers de pinning configurados no
    // $HOME real, o que seria não-determinístico e dependente de máquina
    // aqui. Rejeitar nunca chama `pin`, então cobre o roteamento/wiring de
    // ponta a ponta sem depender de infraestrutura de IPFS.

    #[tokio::test]
    async fn pin_endpoint_new_app_request_parks_and_can_be_rejected() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let pin_requests = temp_pin_state();
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            pin_requests.clone(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/pin", base_url(&started));
        let request = reqwest::Client::new().post(&url).json(&serde_json::json!({
            "appName": "Practice Valuation",
            "contentBase64": "aGVsbG8=",
        }));

        let (resp, _) = tokio::join!(request.send(), async {
            let id = loop {
                if let Some(payload) = pin::current(&pin_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            pin::resolve(&pin_requests, &id, pin::PinDecision::Rejected)
                .await
                .expect("resolve should succeed");
        });

        let resp = resp.expect("request should succeed");
        assert_eq!(resp.status(), 403);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["status"], "rejected");

        stop(&state).await;
    }

    #[tokio::test]
    async fn pin_endpoint_rejects_concurrent_second_request() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let pin_requests = temp_pin_state();
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            pin_requests.clone(),
            |_| {},
            temp_vault_edit_state(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/pin", base_url(&started));
        let body = serde_json::json!({
            "appName": "Practice Valuation",
            "contentBase64": "aGVsbG8=",
        });

        let first_request = reqwest::Client::new().post(&url).json(&body).send();
        let second_request = async {
            let id = loop {
                if let Some(payload) = pin::current(&pin_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            let resp = reqwest::Client::new().post(&url).json(&body).send().await;
            pin::resolve(&pin_requests, &id, pin::PinDecision::Rejected)
                .await
                .expect("resolve should succeed");
            resp
        };

        let (first, second) = tokio::join!(first_request, second_request);
        assert_eq!(second.expect("request should succeed").status(), 409);
        assert_eq!(first.expect("request should succeed").status(), 403);

        stop(&state).await;
    }

    // Roteamento de /truthid/v1/vault-edit — mesmo espírito dos testes de
    // /pin acima: só exercita o caminho Rejected (aprovar de verdade
    // dispara merge+publish, que é orquestrado pelo frontend, fora do
    // escopo deste teste de wiring).

    #[tokio::test]
    async fn vault_edit_endpoint_parks_until_resolved_and_can_be_rejected() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let vault_edit_requests = temp_vault_edit_state();
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            temp_pin_state(),
            |_| {},
            vault_edit_requests.clone(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/vault-edit", base_url(&started));
        let request = reqwest::Client::new().post(&url).json(&serde_json::json!({
            "site": "example.com",
            "username": "user",
            "password": "hunter2",
        }));

        let (resp, _) = tokio::join!(request.send(), async {
            let id = loop {
                if let Some(payload) = vault_edit::current(&vault_edit_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            vault_edit::resolve(&vault_edit_requests, &id, vault_edit::VaultEditDecision::Rejected)
                .await
                .expect("resolve should succeed");
        });

        let resp = resp.expect("request should succeed");
        assert_eq!(resp.status(), 403);
        let body: serde_json::Value = resp.json().await.expect("valid json");
        assert_eq!(body["status"], "rejected");

        stop(&state).await;
    }

    #[tokio::test]
    async fn vault_edit_endpoint_rejects_concurrent_second_request() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();
        let vault_edit_requests = temp_vault_edit_state();
        let started = start(
            &state,
            Arc::new(SignRequestState::default()),
            |_| {},
            Arc::new(SignMessageState::default()),
            |_| {},
            temp_pin_state(),
            |_| {},
            vault_edit_requests.clone(),
            |_| {},
        )
        .await
        .expect("start should succeed");

        let url = format!("{}/truthid/v1/vault-edit", base_url(&started));
        let body = serde_json::json!({
            "site": "example.com",
            "username": "user",
            "password": "hunter2",
        });

        let first_request = reqwest::Client::new().post(&url).json(&body).send();
        let second_request = async {
            let id = loop {
                if let Some(payload) = vault_edit::current(&vault_edit_requests).await {
                    break payload.id;
                }
                tokio::task::yield_now().await;
            };
            let resp = reqwest::Client::new().post(&url).json(&body).send().await;
            vault_edit::resolve(&vault_edit_requests, &id, vault_edit::VaultEditDecision::Rejected)
                .await
                .expect("resolve should succeed");
            resp
        };

        let (first, second) = tokio::join!(first_request, second_request);
        assert_eq!(second.expect("request should succeed").status(), 409);
        assert_eq!(first.expect("request should succeed").status(), 403);

        stop(&state).await;
    }
}

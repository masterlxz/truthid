use std::net::{Ipv4Addr, SocketAddr};

use axum::{extract::Json, http::StatusCode, routing::get, routing::post, Router};
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio::sync::{oneshot, Mutex};

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

fn router() -> Router {
    Router::new()
        .route("/truthid/v1/ping", get(ping))
        .route("/truthid/v1/handshake", post(handshake))
}

/// Sobe o servidor na primeira porta livre de CANDIDATE_PORTS, bindada em
/// 127.0.0.1 (nunca 0.0.0.0 — os dois processos estão sempre na mesma
/// máquina, então loopback já é suficiente e é bem mais seguro). Idempotente:
/// se já estiver rodando, devolve o status atual sem religar.
pub async fn start(state: &LocalSignerServerState) -> Result<LocalSignerStatus, String> {
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

    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let join_handle = tauri::async_runtime::spawn(async move {
        let _ = axum::serve(listener, router())
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
pub async fn stop(state: &LocalSignerServerState) -> LocalSignerStatus {
    let mut guard = state.0.lock().await;
    if let Some(running) = guard.take() {
        let _ = running.shutdown_tx.send(());
        let _ = running.join_handle.await;
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

    #[tokio::test]
    async fn start_binds_to_a_candidate_port_and_status_reflects_it() {
        let _guard = PORT_TEST_LOCK.lock().await;
        let state = LocalSignerServerState::default();

        let started = start(&state).await.expect("start should succeed");
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
        let started = start(&state).await.expect("start should succeed");

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
        let started = start(&state).await.expect("start should succeed");

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
        let started = start(&state).await.expect("start should succeed");

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
        let started = start(&state).await.expect("start should succeed");

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

        let first = start(&state).await.expect("first start should succeed");
        stop(&state).await;

        let second = start(&state).await.expect("second start should succeed");
        assert_eq!(first.port, second.port);

        let resp = reqwest::get(format!("{}/truthid/v1/ping", base_url(&second)))
            .await
            .expect("server should respond after restart");
        assert_eq!(resp.status(), 200);

        stop(&state).await;
    }
}

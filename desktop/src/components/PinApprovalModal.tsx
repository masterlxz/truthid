import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useIncomingPinRequest } from "../hooks/useIncomingPinRequest";
import { respondToRequest } from "../services/respondToRequest";

/**
 * Aprovação de /truthid/v1/pin — só aparece quando o app precisa de
 * aprovação humana (app novo, ou cota diária estourada). Um app já
 * autorizado e dentro da cota pina direto no Rust, sem popup nenhum;
 * aprovar aqui autoriza o app a usar os providers de pinning já
 * configurados no TruthID (ver VaultSettings) pelo limite diário indicado —
 * a chave de API dos providers nunca sai do Rust.
 */
export function PinApprovalModal() {
  const { request, clear } = useIncomingPinRequest();
  const [expired, setExpired] = useState(false);

  // Failsafe local: o Rust já libera o pedido sozinho aos 5min (408 pro app
  // terceiro), isso só fecha o modal de quem ficou olhando a tela.
  useEffect(() => {
    if (!request) { setExpired(false); return; }
    setExpired(Date.now() > request.expiresAtMs);
    const timer = setInterval(() => {
      if (Date.now() > request.expiresAtMs) {
        setExpired(true);
        clearInterval(timer);
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [request]);

  if (!request) return null;

  async function handleApprove() {
    if (!request) return;
    await invoke("respond_to_pin_request", {
      id: request.id,
      decision: { outcome: "approved" },
    }).catch(() => {});
    clear();
  }

  async function handleReject() {
    if (!request) return;
    respondToRequest("respond_to_pin_request", request.id, clear);
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">Pinning request</h2>
        </div>

        <div className="card">
          {request.reason === "newApp" ? (
            <p>
              <strong>{request.appName || "An app"}</strong> wants to use your configured IPFS
              pinning providers. Content is always sent already encrypted — TruthID never sees
              or stores it in plain text, and provider API keys never leave this device.
            </p>
          ) : (
            <p>
              <strong>{request.appName || "An app"}</strong> reached its daily pinning limit.
              Approving grants a fresh {request.dailyLimit}-pin window starting now.
            </p>
          )}

          {request.reason === "newApp" && (
            <p className="muted" style={{ marginTop: "0.5rem" }}>
              Suggested daily limit: {request.dailyLimit} pins. After approving, further
              requests from this app won't need approval until the limit is reached.
            </p>
          )}

          {expired && <p className="error-text">This request has expired.</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleApprove} disabled={expired}>
              Approve
            </button>
            <button onClick={handleReject} className="topbar-btn-danger">
              Reject
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

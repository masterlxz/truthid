import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useIncomingSignMessage } from "../hooks/useIncomingSignMessage";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { respondToRequest } from "../services/respondToRequest";

/**
 * Aprovação de /truthid/v1/sign-message — mais simples que o SignRequestModal
 * porque não há UserOp/wallet envolvidos: a assinatura acontece inteira no
 * Rust (com a device key local) dentro da própria requisição HTTP pendurada.
 * O clique aqui só libera o oneshot que o Rust está esperando; nenhum estado
 * de "signing..." é necessário do lado do frontend.
 */
export function SignMessageModal() {
  const { request, clear } = useIncomingSignMessage();
  const [error, setError] = useState<string | null>(null);
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);

  if (!request) return null;

  async function handleApprove() {
    if (!request) return;
    setError(null);
    try {
      await invoke("respond_to_sign_message", {
        id: request.id,
        decision: { outcome: "approved" },
      });
      clear();
    } catch (e) {
      setError(String(e));
    }
  }

  async function handleReject() {
    if (!request) return;
    respondToRequest("respond_to_sign_message", request.id, clear);
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">Sign message</h2>
        </div>

        <div className="card">
          <p>
            <strong>{request.appName || "An app"}</strong> wants to derive a signing key for
            itself (purpose: <code>{request.purpose}</code>).
          </p>

          <p className="muted" style={{ marginTop: "0.5rem" }}>
            Exact message that will be signed:
          </p>
          <code className="address" style={{ display: "block" }}>
            {request.message}
          </code>

          {expired && <p className="error-text">This request has expired.</p>}
          {error && <p className="error-text">{error}</p>}

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

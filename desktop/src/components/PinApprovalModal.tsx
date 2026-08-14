import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useIncomingPinRequest } from "../hooks/useIncomingPinRequest";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { respondToRequest } from "../services/respondToRequest";

/**
 * Aprovação de /truthid/v1/pin — toda requisição passa por aqui, sempre
 * (decisão do dono do projeto: aprovação por chamada, mesmo padrão do
 * SignMessageModal, sem autorização persistida por app). Aprovar publica o
 * conteúdo no Arweave usando a wallet local já configurada no TruthID (ver
 * VaultSettings) — a chave privada da wallet nunca sai do Rust.
 */
export function PinApprovalModal() {
  const { request, clear } = useIncomingPinRequest();
  const [error, setError] = useState<string | null>(null);
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);

  if (!request) return null;

  async function handleApprove() {
    if (!request) return;
    setError(null);
    try {
      await invoke("respond_to_pin_request", {
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
    respondToRequest("respond_to_pin_request", request.id, clear);
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">Pinning request</h2>
        </div>

        <div className="card">
          <p>
            <strong>{request.appName || "An app"}</strong> wants to publish content using your
            configured Arweave wallet. Content is always sent already encrypted — TruthID never
            sees or stores it in plain text.
          </p>

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

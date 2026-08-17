import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { useIncomingAutofillAddressRequest } from "../hooks/useIncomingAutofillAddressRequest";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { respondToRequest } from "../services/respondToRequest";

/**
 * Aprovação de /truthid/v1/autofill-address (Fase 15.4, fatia 2 — Desktop) —
 * a extensão de navegador pede um dos endereços salvos no Vault pra
 * preencher um formulário. Ao contrário do /pin e /vault-edit, este canal
 * não recebe dado nenhum no corpo do POST: o próprio Rust já leu o Vault
 * local e mandou a lista de candidatos no payload (`candidates`) — aqui só
 * escolhe qual usar, sem passo de confirmação separado (loopback já é
 * mesmo nível de confiança do próprio usuário na própria máquina).
 */
export function AutofillAddressApprovalModal() {
  const { t } = useTranslation();
  const { request, clear } = useIncomingAutofillAddressRequest();
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);

  if (!request) return null;

  async function handleApprove(entryId: string) {
    await invoke("respond_to_autofill_address_request", {
      id: request!.id,
      decision: { outcome: "approved", entryId },
    }).catch(() => {});
    clear();
  }

  function handleReject() {
    respondToRequest("respond_to_autofill_address_request", request!.id, clear);
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">{t("autofillAddressApprovalModal.title")}</h2>
        </div>

        <div className="card">
          <p>{t("autofillAddressApprovalModal.description")}</p>

          {request.candidates.map((candidate) => (
            <div
              key={candidate.entryId}
              className="card"
              style={{ marginTop: "0.75rem", background: "var(--bg-alt, transparent)" }}
            >
              <p style={{ fontWeight: 600, margin: 0 }}>{candidate.data.label}</p>
              <p className="muted" style={{ marginTop: "0.25rem" }}>
                {candidate.data.street}, {candidate.data.number} · {candidate.data.city}/
                {candidate.data.state} · {candidate.data.zip_code}
              </p>
              <div className="actions-row" style={{ marginTop: "0.5rem" }}>
                <button onClick={() => handleApprove(candidate.entryId)} disabled={expired}>
                  {t("autofillAddressApprovalModal.useThisAddress")}
                </button>
              </div>
            </div>
          ))}

          {expired && <p className="error-text">{t("autofillAddressApprovalModal.expired")}</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleReject} className="topbar-btn-danger">
              {t("autofillAddressApprovalModal.denyRequest")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

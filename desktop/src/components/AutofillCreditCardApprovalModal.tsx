import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { useIncomingAutofillCreditCardRequest } from "../hooks/useIncomingAutofillCreditCardRequest";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { respondToRequest } from "../services/respondToRequest";

/**
 * Aprovação de /truthid/v1/autofill-creditcard (Fase 15.4, fatia 2 —
 * Desktop) — mesmo desenho de `AutofillAddressApprovalModal`, mas número/CVV
 * começam mascarados por candidato (mesmo cuidado que
 * `autofill_creditcard_approval_screen.dart` já tem no Mobile — dado mais
 * sensível que endereço, mesmo em loopback).
 */
export function AutofillCreditCardApprovalModal() {
  const { t } = useTranslation();
  const { request, clear } = useIncomingAutofillCreditCardRequest();
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);
  const [visible, setVisible] = useState<Set<string>>(new Set());

  if (!request) return null;

  function toggleVisible(entryId: string) {
    setVisible((prev) => {
      const next = new Set(prev);
      if (next.has(entryId)) next.delete(entryId);
      else next.add(entryId);
      return next;
    });
  }

  async function handleApprove(entryId: string) {
    await invoke("respond_to_autofill_creditcard_request", {
      id: request!.id,
      decision: { outcome: "approved", entryId },
    }).catch(() => {});
    clear();
  }

  function handleReject() {
    respondToRequest("respond_to_autofill_creditcard_request", request!.id, clear);
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">{t("autofillCreditCardApprovalModal.title")}</h2>
        </div>

        <div className="card">
          <p>{t("autofillCreditCardApprovalModal.description")}</p>

          {request.candidates.map((candidate) => {
            const shown = visible.has(candidate.entryId);
            const last4 = candidate.data.card_number.slice(-4);
            return (
              <div
                key={candidate.entryId}
                className="card"
                style={{ marginTop: "0.75rem", background: "var(--bg-alt, transparent)" }}
              >
                <p style={{ fontWeight: 600, margin: 0 }}>{candidate.data.label}</p>
                <p className="muted" style={{ marginTop: "0.25rem" }}>
                  {candidate.data.card_network} {shown ? candidate.data.card_number : `•••• ${last4}`} ·{" "}
                  {candidate.data.expiry_month}/{candidate.data.expiry_year}
                  {shown && t("autofillCreditCardApprovalModal.cvvSuffix", { cvv: candidate.data.cvv })}
                </p>
                <div className="actions-row" style={{ marginTop: "0.5rem" }}>
                  <button onClick={() => handleApprove(candidate.entryId)} disabled={expired}>
                    {t("autofillCreditCardApprovalModal.useThisCard")}
                  </button>
                  <button type="button" onClick={() => toggleVisible(candidate.entryId)}>
                    {shown ? t("autofillCreditCardApprovalModal.hide") : t("autofillCreditCardApprovalModal.show")}
                  </button>
                </div>
              </div>
            );
          })}

          {expired && <p className="error-text">{t("autofillCreditCardApprovalModal.expired")}</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleReject} className="topbar-btn-danger">
              {t("autofillCreditCardApprovalModal.denyRequest")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

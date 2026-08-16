import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { Address } from "viem";
import { useIncomingVaultEditRequest } from "../hooks/useIncomingVaultEditRequest";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { publishVaultViaDeviceKey } from "../services/vaultPublishViaDeviceKey";
import { respondToRequest } from "../services/respondToRequest";
import type { VaultEntry } from "../types";

/**
 * Aprovação de /truthid/v1/vault-edit — propostas de credencial nova vindas
 * da extensão de navegador (item 6 do roadmap, Sessão 134). Ao contrário do
 * /pin, toda proposta pede aprovação (sem cota) e o merge+publicação
 * acontece aqui mesmo, no clique — reaproveitando os 2 comandos que o botão
 * "Publicar via device key" (VaultManagement.tsx) já usa.
 */
export function VaultEditApprovalModal({
  smartAccountAddress,
}: {
  smartAccountAddress?: Address | null;
}) {
  const { request, clear } = useIncomingVaultEditRequest();
  // Sync em lote (P29): visibilidade de senha é por item, não mais um único
  // booleano — um Set dos índices que o usuário revelou.
  const [visiblePasswords, setVisiblePasswords] = useState<Set<number>>(new Set());
  const [stage, setStage] = useState<"idle" | "publishing" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);

  // Quando o pedido muda (novo ou cancelado), reseta o estado do modal.
  useEffect(() => {
    if (!request) { setVisiblePasswords(new Set()); setStage("idle"); setError(null); }
  }, [request]);

  function togglePasswordVisible(index: number) {
    setVisiblePasswords((prev) => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  }

  if (!request) return null;

  async function handleApprove() {
    if (!request) return;
    if (!smartAccountAddress) {
      setError("No identity loaded — cannot publish.");
      setStage("error");
      return;
    }
    setStage("publishing");
    setError(null);
    try {
      // Sync em lote (P29): persiste cada proposta localmente primeiro, e só
      // publica UMA vez no fim — reaproveita exatamente o mesmo caminho de
      // publish de sempre, só que cobrindo N entradas em vez de 1.
      for (const proposal of request.entries) {
        const entry: VaultEntry = {
          id: proposal.targetEntryId ?? "",
          site: proposal.site,
          url: proposal.url,
          username: proposal.username,
          password: proposal.password,
          notes: proposal.notes,
          profiles: [],
          passkey: proposal.passkey,
          favorite: false,
          type: "credential",
          created_at: 0,
          updated_at: 0,
        };
        await invoke<VaultEntry>("vault_upsert_entry", { entry });
      }
      await publishVaultViaDeviceKey(smartAccountAddress);

      // Só responde ao Rust depois que o vault foi salvo e publicado.
      // Se algo falhar aqui, o slot do Rust continua pendente — o
      // usuário pode clicar Approve de novo (#9). E nenhuma segunda
      // proposta entra entre o respond e o upsert (#10).
      await invoke("respond_to_vault_edit_request", {
        id: request.id,
        decision: { outcome: "approved" },
      });

      clear();
    } catch (e) {
      setError(String(e));
      setStage("error");
    }
  }

  async function handleReject() {
    if (!request) return;
    respondToRequest("respond_to_vault_edit_request", request.id, clear);
  }

  const { entries } = request;
  const title =
    entries.length === 1
      ? "New credential from extension"
      : `${entries.length} new credentials from extension`;

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">{title}</h2>
        </div>

        <div className="card">
          <p>
            {entries.length === 1
              ? "The TruthID browser extension wants to save a new credential to your Vault."
              : `The TruthID browser extension wants to save ${entries.length} new credentials to your Vault.`}
          </p>

          {entries.map((entry, index) => (
            <div
              key={index}
              className="card"
              style={{ marginTop: "0.75rem", background: "var(--bg-alt, transparent)" }}
            >
              <div className="field">
                <label>Site</label>
                <input value={entry.site} readOnly />
              </div>
              <p className="muted" style={{ marginTop: "0.35rem", marginBottom: 0 }}>
                {entry.targetEntryId ? "Updating existing entry" : "New entry"}
              </p>
              {entry.username && (
                <div className="field" style={{ marginTop: "0.5rem" }}>
                  <label>Username</label>
                  <input value={entry.username} readOnly />
                </div>
              )}
              {entry.password && (
                <div className="field" style={{ marginTop: "0.5rem" }}>
                  <label>Password</label>
                  <div style={{ display: "flex", gap: "0.4rem" }}>
                    <input
                      style={{ flex: 1 }}
                      type={visiblePasswords.has(index) ? "text" : "password"}
                      value={entry.password}
                      readOnly
                    />
                    <button type="button" onClick={() => togglePasswordVisible(index)}>
                      {visiblePasswords.has(index) ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
              )}
              {entry.passkey && (
                <p className="muted" style={{ marginTop: "0.5rem" }}>
                  🔑 + new passkey for {entry.passkey.rp_id}
                </p>
              )}
            </div>
          ))}

          {expired && <p className="error-text">This request has expired.</p>}
          {error && <p className="error-text">{error}</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleApprove} disabled={expired || stage === "publishing"}>
              {stage === "publishing" ? "Publishing..." : "Approve"}
            </button>
            <button
              onClick={handleReject}
              className="topbar-btn-danger"
              disabled={stage === "publishing"}
            >
              Reject
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

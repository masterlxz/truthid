import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { Address } from "viem";
import { useIncomingVaultEditRequest } from "../hooks/useIncomingVaultEditRequest";
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
  const [expired, setExpired] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [stage, setStage] = useState<"idle" | "publishing" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  // Failsafe local: o Rust já libera o pedido sozinho aos 5min (408 pra
  // extensão), isso só fecha o modal de quem ficou olhando a tela.
  useEffect(() => {
    if (!request) { setExpired(false); setShowPassword(false); setStage("idle"); setError(null); return; }
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
    if (!smartAccountAddress) {
      setError("Nenhuma identidade carregada — não é possível publicar.");
      setStage("error");
      return;
    }
    setStage("publishing");
    setError(null);
    try {
      const entry: VaultEntry = {
        id: "",
        site: request.entry.site,
        url: request.entry.url,
        username: request.entry.username,
        password: request.entry.password,
        notes: request.entry.notes,
        profiles: [],
        passkey: request.entry.passkey,
        favorite: false,
        created_at: 0,
        updated_at: 0,
      };
      await invoke<VaultEntry>("vault_upsert_entry", { entry });
      const { providersFailed } = await publishVaultViaDeviceKey(smartAccountAddress);

      // Só responde ao Rust depois que o vault foi salvo e publicado.
      // Se algo falhar aqui, o slot do Rust continua pendente — o
      // usuário pode clicar Approve de novo (#9). E nenhuma segunda
      // proposta entra entre o respond e o upsert (#10).
      await invoke("respond_to_vault_edit_request", {
        id: request.id,
        decision: { outcome: "approved" },
      });

      if (providersFailed.length > 0) {
        console.warn(
          `Vault published with partial pinning redundancy: ${providersFailed.join(", ")} failed.`
        );
      }

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

  const { entry } = request;

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">New credential from extension</h2>
        </div>

        <div className="card">
          <p>
            The TruthID browser extension wants to save a new credential to your Vault.
          </p>

          <div className="field" style={{ marginTop: "0.75rem" }}>
            <label>Site</label>
            <input value={entry.site} readOnly />
          </div>
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
                  type={showPassword ? "text" : "password"}
                  value={entry.password}
                  readOnly
                />
                <button type="button" onClick={() => setShowPassword((s) => !s)}>
                  {showPassword ? "Hide" : "Show"}
                </button>
              </div>
            </div>
          )}
          {entry.passkey && (
            <p className="muted" style={{ marginTop: "0.5rem" }}>
              🔑 + new passkey for {entry.passkey.rp_id}
            </p>
          )}

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

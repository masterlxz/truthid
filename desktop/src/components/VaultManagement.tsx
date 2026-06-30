import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  VAULT_REGISTRY_ADDRESS,
  VAULT_REGISTRY_ABI,
} from "../config/contracts";
import type { DeviceInfo, VaultEntry, PinResult, DeviceVaultPermission } from "../types";
import { VaultSettings } from "./VaultSettings";

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const PROFILES = ["Trabalho", "Casa", "Pessoal"];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function maskPassword(p: string) {
  return p.length > 0 ? "•".repeat(Math.min(p.length, 12)) : "";
}

function formatTs(secs: number) {
  return new Date(secs * 1000).toLocaleDateString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric",
  });
}

function truncate(s: string, n = 10) {
  return s.length > n * 2 + 3 ? `${s.slice(0, n)}…${s.slice(-n)}` : s;
}

type FormState = {
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  profiles: string[];
};

function emptyForm(): FormState {
  return { site: "", url: "", username: "", password: "", notes: "", profiles: [] };
}

// ---------------------------------------------------------------------------
// Sub-componente: seletor de grupos
// ---------------------------------------------------------------------------

function ProfilePicker({
  value,
  onChange,
}: {
  value: string[];
  onChange: (v: string[]) => void;
}) {
  function toggle(p: string) {
    onChange(value.includes(p) ? value.filter((x) => x !== p) : [...value, p]);
  }
  return (
    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
      {PROFILES.map((p) => (
        <button
          key={p}
          type="button"
          onClick={() => toggle(p)}
          style={{
            padding: "0.25em 0.75em",
            fontSize: "0.82em",
            borderColor: value.includes(p) ? "var(--color-accent)" : "var(--color-border)",
            color: value.includes(p) ? "var(--color-accent)" : "var(--color-text-muted)",
            background: value.includes(p) ? "rgba(77,208,225,0.1)" : "transparent",
          }}
        >
          {value.includes(p) ? "✓ " : ""}{p}
        </button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-componente: formulário de entrada (add / edit)
// ---------------------------------------------------------------------------

function EntryForm({
  initial,
  onSave,
  onCancel,
  saving,
}: {
  initial: FormState;
  onSave: (f: FormState) => void;
  onCancel: () => void;
  saving: boolean;
}) {
  const [form, setForm] = useState<FormState>(initial);
  const [showPw, setShowPw] = useState(false);

  function set(field: keyof FormState, val: string | string[]) {
    setForm((f) => ({ ...f, [field]: val }));
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "0.6rem" }}>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.6rem" }}>
        <div className="field">
          <label>Site *</label>
          <input value={form.site} onChange={(e) => set("site", e.target.value)} placeholder="ex: github.com" />
        </div>
        <div className="field">
          <label>URL</label>
          <input value={form.url} onChange={(e) => set("url", e.target.value)} placeholder="https://..." />
        </div>
        <div className="field">
          <label>Usuário *</label>
          <input value={form.username} onChange={(e) => set("username", e.target.value)} placeholder="@usuário ou email" />
        </div>
        <div className="field">
          <label>Senha *</label>
          <div style={{ display: "flex", gap: "0.4rem" }}>
            <input
              type={showPw ? "text" : "password"}
              value={form.password}
              onChange={(e) => set("password", e.target.value)}
              placeholder="••••••••"
              style={{ flex: 1 }}
            />
            <button type="button" onClick={() => setShowPw((v) => !v)} style={{ padding: "0.3em 0.6em", fontSize: "0.9em" }}>
              {showPw ? "🙈" : "👁"}
            </button>
          </div>
        </div>
      </div>
      <div className="field">
        <label>Notas</label>
        <input value={form.notes} onChange={(e) => set("notes", e.target.value)} placeholder="notas opcionais" />
      </div>
      <div className="field">
        <label>Grupos</label>
        <ProfilePicker value={form.profiles} onChange={(v) => set("profiles", v)} />
      </div>
      <div className="actions-row">
        <button
          onClick={() => onSave(form)}
          disabled={saving || !form.site.trim() || !form.username.trim() || !form.password.trim()}
        >
          {saving ? "Salvando..." : "Salvar"}
        </button>
        <button
          onClick={onCancel}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)" }}
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Componente principal
// ---------------------------------------------------------------------------

export function VaultManagement() {
  const { identityId } = useIdentity();
  const { isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();

  // ── View ──────────────────────────────────────────────────────────────────
  const [view, setView] = useState<"entries" | "settings">("entries");

  // ── Entradas locais ───────────────────────────────────────────────────────
  const [entries, setEntries] = useState<VaultEntry[]>([]);
  const [loadingEntries, setLoadingEntries] = useState(true);
  const [pendingCount, setPendingCount] = useState(0);
  const [filter, setFilter] = useState("");

  // ── Add / edit / delete ──────────────────────────────────────────────────
  const [addOpen, setAddOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [mutating, setMutating] = useState(false);
  const [mutateError, setMutateError] = useState<string | null>(null);

  // ── Publicação (vault_publish + on-chain updateVault) ────────────────────
  const [publishState, setPublishState] = useState<"idle" | "publishing" | "error">("idle");
  const [publishError, setPublishError] = useState<string | null>(null);
  const [pendingUpdate, setPendingUpdate] = useState<{
    cid: string;
    contentHash: `0x${string}`;
  } | null>(null);
  const [justPublished, setJustPublished] = useState(false);

  // ── Wagmi: publicação on-chain ────────────────────────────────────────────
  const {
    writeContract,
    data: txHash,
    isPending: isTxPending,
    isError: isTxError,
    error: txError,
    reset: resetTx,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isTxSuccess } =
    useWaitForTransactionReceipt({ hash: txHash });

  // ── On-chain: status do vault ─────────────────────────────────────────────
  const { data: hasVault, refetch: refetchHasVault } = useReadContract({
    address: VAULT_REGISTRY_ADDRESS,
    abi: VAULT_REGISTRY_ABI,
    functionName: "hasVault",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  const { data: vaultRef, refetch: refetchVaultRef } = useReadContract({
    address: VAULT_REGISTRY_ADDRESS,
    abi: VAULT_REGISTRY_ABI,
    functionName: "getVault",
    args: [identityId!],
    query: { enabled: !!identityId && !!hasVault },
  });

  // ── On-chain: devices (para seção de permissões) ──────────────────────────
  const { data: devicePubKeys } = useReadContract({
    address: DEVICE_REGISTRY_ADDRESS,
    abi: DEVICE_REGISTRY_ABI,
    functionName: "getDevicesByIdentity",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  const { data: deviceResults } = useReadContracts({
    contracts: (devicePubKeys ?? []).map((pk) => ({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice" as const,
      args: [pk] as const,
    })),
    query: { enabled: !!devicePubKeys && devicePubKeys.length > 0 },
  });

  const devices = (deviceResults ?? [])
    .map((r) => r.result)
    .filter(Boolean) as DeviceInfo[];

  const activeDevices = devices.filter((d) => !d.revoked);

  // ── Permissões locais ────────────────────────────────────────────────────
  const [permissions, setPermissions] = useState<DeviceVaultPermission[]>([]);
  const [permsOpen, setPermsOpen] = useState(false);

  // ── Carregamento inicial ──────────────────────────────────────────────────
  async function loadAll() {
    setLoadingEntries(true);
    try {
      const [e, p, perms] = await Promise.all([
        invoke<VaultEntry[]>("vault_list_entries"),
        invoke<number>("vault_pending_changes"),
        invoke<DeviceVaultPermission[]>("vault_get_device_permissions"),
      ]);
      setEntries(e);
      setPendingCount(p);
      setPermissions(perms);
    } catch {
      // sem vault ainda — tudo vazio é ok
    } finally {
      setLoadingEntries(false);
    }
  }

  useEffect(() => { loadAll(); }, []);

  // ── Dispara updateVault quando vault_publish retornar ────────────────────
  useEffect(() => {
    if (!pendingUpdate) return;
    if (!isConnected) { openConnectModal(); return; }
    writeContract({
      address: VAULT_REGISTRY_ADDRESS,
      abi: VAULT_REGISTRY_ABI,
      functionName: "updateVault",
      args: [pendingUpdate.cid, pendingUpdate.contentHash],
    });
    setPendingUpdate(null);
  }, [pendingUpdate]);

  useEffect(() => {
    if (isTxSuccess) {
      refetchHasVault();
      refetchVaultRef();
      setPendingCount(0);
      setJustPublished(true);
      setTimeout(() => setJustPublished(false), 3000);
      resetTx();
    }
  }, [isTxSuccess]);

  // ── Publicar ─────────────────────────────────────────────────────────────
  async function handleEnviar() {
    setPublishError(null);
    setPublishState("publishing");
    try {
      const result = await invoke<PinResult>("vault_publish");
      if (result.providers_failed.length > 0 && result.providers_ok.length === 0) {
        throw new Error(`Todos os providers falharam: ${result.providers_failed.join(", ")}`);
      }
      setPendingUpdate({ cid: result.cid, contentHash: result.content_hash as `0x${string}` });
      setPublishState("idle");
    } catch (e) {
      setPublishError(String(e));
      setPublishState("error");
    }
  }

  function publishButtonLabel() {
    if (publishState === "publishing") return "Publicando no IPFS...";
    if (isTxPending) return "Confirmar na carteira...";
    if (isConfirming) return "Aguardando rede...";
    if (justPublished) return "Enviado ✓";
    if (pendingCount > 0) return `Enviar (${pendingCount} pendente${pendingCount > 1 ? "s" : ""})`;
    return "Enviar";
  }

  // ── CRUD de entradas ──────────────────────────────────────────────────────
  async function handleAdd(form: FormState) {
    setMutating(true);
    setMutateError(null);
    try {
      const entry: Partial<VaultEntry> = { ...form, id: "" };
      await invoke<VaultEntry>("vault_upsert_entry", { entry: { ...entry, id: "", created_at: 0, updated_at: 0 } });
      await loadAll();
      setAddOpen(false);
    } catch (e) {
      setMutateError(String(e));
    } finally {
      setMutating(false);
    }
  }

  async function handleEdit(id: string, form: FormState) {
    const original = entries.find((e) => e.id === id)!;
    setMutating(true);
    setMutateError(null);
    try {
      await invoke<VaultEntry>("vault_upsert_entry", {
        entry: { ...original, ...form },
      });
      await loadAll();
      setEditingId(null);
    } catch (e) {
      setMutateError(String(e));
    } finally {
      setMutating(false);
    }
  }

  async function handleDelete(id: string) {
    setMutating(true);
    try {
      await invoke<void>("vault_delete_entry", { id });
      await loadAll();
      setDeletingId(null);
    } catch (e) {
      setMutateError(String(e));
    } finally {
      setMutating(false);
    }
  }

  // ── Permissões ───────────────────────────────────────────────────────────
  async function handleTogglePerm(pubKey: string, canWrite: boolean) {
    try {
      await invoke<void>("vault_set_device_permission", { pub_key: pubKey, can_write: canWrite });
      setPermissions((prev) => {
        const existing = prev.find((p) => p.pub_key === pubKey);
        if (existing) return prev.map((p) => p.pub_key === pubKey ? { ...p, can_write: canWrite } : p);
        return [...prev, { pub_key: pubKey, can_write: canWrite }];
      });
    } catch { /* ignora */ }
  }

  // ── Filtragem ─────────────────────────────────────────────────────────────
  const filtered = filter.trim()
    ? entries.filter((e) =>
        e.site.toLowerCase().includes(filter.toLowerCase()) ||
        e.username.toLowerCase().includes(filter.toLowerCase()) ||
        e.profiles.some((p) => p.toLowerCase().includes(filter.toLowerCase()))
      )
    : entries;

  // ── View: settings ────────────────────────────────────────────────────────
  if (view === "settings") {
    return (
      <div>
        <div style={{ display: "flex", alignItems: "center", gap: "1rem", marginBottom: "1rem" }}>
          <button
            onClick={() => setView("entries")}
            style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", padding: "0.3em 0.8em" }}
          >
            ← Vault
          </button>
          <h2 style={{ margin: 0 }}>Providers de Pinning</h2>
        </div>
        <VaultSettings />
      </div>
    );
  }

  // ── View: entries ─────────────────────────────────────────────────────────
  return (
    <div>
      {/* Cabeçalho */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "1rem" }}>
        <h2 style={{ margin: 0 }}>Vault</h2>
        <button
          onClick={() => setView("settings")}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", padding: "0.3em 0.8em", fontSize: "0.85em" }}
        >
          ⚙ Providers
        </button>
      </div>

      {/* Status on-chain + botão Enviar */}
      <div className="card" style={{ marginBottom: "1rem" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            {hasVault === undefined ? (
              <span className="muted">Verificando status on-chain...</span>
            ) : hasVault ? (
              <span className="muted">
                Versão <strong>{String((vaultRef as any)?.version ?? "?")}</strong> registrada on-chain
                {(vaultRef as any)?.updatedAt
                  ? ` · atualizado em ${formatTs(Number((vaultRef as any).updatedAt))}`
                  : ""}
              </span>
            ) : (
              <span className="muted">Vault ainda não registrado on-chain</span>
            )}
          </div>
          <button
            onClick={handleEnviar}
            disabled={publishState === "publishing" || isTxPending || isConfirming || justPublished}
          >
            {publishButtonLabel()}
          </button>
        </div>

        {publishState === "error" && publishError && (
          <p className="error-text" style={{ marginBottom: 0, marginTop: "0.5rem" }}>
            {publishError}
          </p>
        )}
        {isTxError && txError && (
          <p className="error-text" style={{ marginBottom: 0, marginTop: "0.5rem" }}>
            {txError.message?.split("\n")[0]}
          </p>
        )}
      </div>

      {/* Pesquisa */}
      {entries.length > 0 && (
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Pesquisar por site, usuário ou grupo..."
          style={{ width: "100%", boxSizing: "border-box", marginBottom: "0.75rem" }}
        />
      )}

      {mutateError && <p className="error-text">{mutateError}</p>}

      {/* Lista de entradas */}
      {loadingEntries ? (
        <p className="muted">Carregando...</p>
      ) : filtered.length === 0 && !addOpen ? (
        <p className="muted">{entries.length === 0 ? "Nenhuma senha salva ainda." : "Nenhuma entrada encontrada."}</p>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.6rem", marginBottom: "0.75rem" }}>
          {filtered.map((entry) => {
            if (editingId === entry.id) {
              return (
                <div key={entry.id} className="card">
                  <EntryForm
                    initial={{ site: entry.site, url: entry.url, username: entry.username, password: entry.password, notes: entry.notes, profiles: entry.profiles }}
                    onSave={(f) => handleEdit(entry.id, f)}
                    onCancel={() => setEditingId(null)}
                    saving={mutating}
                  />
                </div>
              );
            }

            return (
              <div key={entry.id} className="card" style={{ padding: "0.75rem 1rem" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", flexWrap: "wrap" }}>
                      <strong>{entry.site}</strong>
                      {entry.profiles.map((p) => (
                        <span key={p} className="status-badge" style={{ fontSize: "0.75em", padding: "0.15em 0.5em" }}>{p}</span>
                      ))}
                    </div>
                    <div className="muted" style={{ fontSize: "0.87em", marginTop: "0.2rem" }}>
                      {entry.username}
                      {entry.url ? <> · <a href={entry.url} target="_blank" rel="noreferrer" style={{ fontSize: "0.9em" }}>{entry.url}</a></> : ""}
                    </div>
                    <div className="address" style={{ fontSize: "0.82em", color: "var(--color-text-muted)", marginTop: "0.15rem" }}>
                      {maskPassword(entry.password)}
                    </div>
                  </div>
                  <div style={{ display: "flex", gap: "0.4rem", flexShrink: 0, marginLeft: "0.75rem" }}>
                    <button
                      onClick={() => { setEditingId(entry.id); setDeletingId(null); }}
                      style={{ padding: "0.3em 0.6em", fontSize: "0.82em" }}
                    >
                      ✎
                    </button>
                    {deletingId === entry.id ? (
                      <>
                        <button
                          onClick={() => handleDelete(entry.id)}
                          disabled={mutating}
                          style={{ padding: "0.3em 0.6em", fontSize: "0.82em", borderColor: "var(--color-danger)", color: "var(--color-danger)" }}
                        >
                          Sim
                        </button>
                        <button
                          onClick={() => setDeletingId(null)}
                          style={{ padding: "0.3em 0.6em", fontSize: "0.82em", borderColor: "var(--color-border)", color: "var(--color-text-muted)" }}
                        >
                          Não
                        </button>
                      </>
                    ) : (
                      <button
                        onClick={() => { setDeletingId(entry.id); setEditingId(null); }}
                        style={{ padding: "0.3em 0.6em", fontSize: "0.82em", borderColor: "var(--color-danger)", color: "var(--color-danger)" }}
                      >
                        ✕
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Formulário de adição */}
      {!addOpen ? (
        <button onClick={() => setAddOpen(true)} style={{ marginBottom: "1.5rem" }}>
          + Nova entrada
        </button>
      ) : (
        <div className="card" style={{ marginBottom: "1.5rem" }}>
          <h3 style={{ marginTop: 0 }}>Nova entrada</h3>
          <EntryForm
            initial={emptyForm()}
            onSave={handleAdd}
            onCancel={() => setAddOpen(false)}
            saving={mutating}
          />
        </div>
      )}

      <hr />

      {/* Permissões por device */}
      <div>
        <button
          onClick={() => setPermsOpen((v) => !v)}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", fontSize: "0.9em", padding: "0.4em 1em" }}
        >
          {permsOpen ? "▼" : "▶"} Permissões por device ({activeDevices.length})
        </button>

        {permsOpen && (
          <div className="card" style={{ marginTop: "0.75rem" }}>
            <p className="muted" style={{ marginTop: 0 }}>
              Controla se um device mobile pode <strong>escrever</strong> no vault (por padrão, só leitura).
              Este desktop sempre tem permissão total.
            </p>
            {activeDevices.length === 0 ? (
              <p className="muted">Nenhum device ativo registrado.</p>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
                {activeDevices.map((d) => {
                  const perm = permissions.find((p) => p.pub_key === d.pubKey);
                  const canWrite = perm?.can_write ?? false;
                  return (
                    <div
                      key={d.pubKey}
                      style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}
                    >
                      <div>
                        <span style={{ fontWeight: 500 }}>{d.label || "Device sem nome"}</span>
                        <span className="address muted" style={{ fontSize: "0.8em", marginLeft: "0.5rem" }}>
                          {truncate(d.pubKey, 8)}
                        </span>
                      </div>
                      <button
                        onClick={() => handleTogglePerm(d.pubKey, !canWrite)}
                        style={{
                          padding: "0.25em 0.75em",
                          fontSize: "0.85em",
                          borderColor: canWrite ? "var(--color-accent)" : "var(--color-border)",
                          color: canWrite ? "var(--color-accent)" : "var(--color-text-muted)",
                        }}
                      >
                        {canWrite ? "✓ Pode escrever" : "Só leitura"}
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { readFile } from "@tauri-apps/plugin-fs";
import { useAccount, useReadContract, useReadContracts, useSignMessage } from "wagmi";
import { hexToSignature } from "viem";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI } from "../config/contracts";
import type { DeviceInfo, VaultEntry, DeviceVaultPermission, Passkey } from "../types";
import { VaultSettings } from "./VaultSettings";
import { VaultBackup } from "./VaultBackup";
import { useVaultPublish } from "../hooks/useVaultPublish";
import { TotpCode } from "./TotpCode";
import { TotpQrScanner } from "./TotpQrScanner";
import { parseTotpSecret } from "../utils/totp";
import { decodeQrFromImageBytes } from "../utils/qrDecode";
import { PasskeyBadge } from "./PasskeyBadge";
import { createPasskey } from "../utils/webauthn";
import { generatePassword, type PasswordGeneratorOptions } from "../utils/passwordGenerator";
import { passwordStrength, type PasswordStrengthScore } from "../utils/passwordStrength";

const VAULT_KEY_MESSAGE = "TruthID Vault Key v1";

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
  totp_secret: string;
  passkey?: Passkey;
};

function emptyForm(): FormState {
  return { site: "", url: "", username: "", password: "", notes: "", profiles: [], totp_secret: "" };
}

/** Extrai um hostname pra usar como RP ID — tenta a URL, cai pro nome do site
 * (sanitizado) se a URL estiver vazia/inválida. Sem redução pra domínio
 * registrável (eTLD+1) nesta fase — não há relying party real validando isso
 * ainda (ver PROJECT_STATE.md, escopo da fundação de Passkeys). */
function hostnameOf(url: string, site: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return site.trim().toLowerCase().replace(/[^a-z0-9.-]/g, "") || "unknown";
  }
}

// ---------------------------------------------------------------------------
// Sub-componente: seletor de grupos
// ---------------------------------------------------------------------------

function ProfilePicker({
  value,
  onChange,
  options,
}: {
  value: string[];
  onChange: (v: string[]) => void;
  options: string[];
}) {
  function toggle(p: string) {
    onChange(value.includes(p) ? value.filter((x) => x !== p) : [...value, p]);
  }
  if (options.length === 0) {
    return <p className="muted" style={{ margin: 0, fontSize: "0.85em" }}>Nenhum perfil criado ainda — crie um em "Gerenciar perfis" abaixo.</p>;
  }
  return (
    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
      {options.map((p) => (
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
// Sub-componente: medidor de força de senha
// ---------------------------------------------------------------------------

const STRENGTH_COLORS: Record<PasswordStrengthScore, string> = {
  0: "var(--color-danger)",
  1: "#e2b25c",
  2: "var(--color-accent)",
  3: "#4caf7d",
};

function StrengthMeter({ password }: { password: string }) {
  if (!password) return null;
  const { score, label } = passwordStrength(password);
  const color = STRENGTH_COLORS[score];
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", marginTop: "0.35rem" }}>
      <div style={{ display: "flex", gap: "3px", flex: 1 }}>
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            style={{
              height: "4px",
              flex: 1,
              borderRadius: "2px",
              background: i <= score ? color : "var(--color-border)",
            }}
          />
        ))}
      </div>
      <span style={{ fontSize: "0.78em", color }}>{label}</span>
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
  profileOptions,
}: {
  initial: FormState;
  onSave: (f: FormState) => void;
  onCancel: () => void;
  saving: boolean;
  profileOptions: string[];
}) {
  const [form, setForm] = useState<FormState>(initial);
  const [showPw, setShowPw] = useState(false);
  const [totpError, setTotpError] = useState<string | null>(null);
  const [genOpen, setGenOpen] = useState(false);
  const [genOptions, setGenOptions] = useState<PasswordGeneratorOptions>({
    length: 16,
    uppercase: true,
    lowercase: true,
    numbers: true,
    symbols: true,
  });
  const [genPreview, setGenPreview] = useState("");
  const [genError, setGenError] = useState<string | null>(null);
  const [qrScannerOpen, setQrScannerOpen] = useState(false);

  function set(field: keyof FormState, val: string | string[]) {
    setForm((f) => ({ ...f, [field]: val }));
  }

  function handleTotpChange(val: string) {
    set("totp_secret", val);
    if (!val.trim()) { setTotpError(null); return; }
    try {
      parseTotpSecret(val);
      setTotpError(null);
    } catch (e) {
      setTotpError(String(e));
    }
  }

  // Aplica um QR escaneado (webcam ou upload) do mesmo jeito que colar o
  // texto manualmente — handleTotpChange já aceita tanto o secret base32 cru
  // quanto a URI otpauth://... completa (parseTotpSecret normaliza no save).
  function handleQrDetected(raw: string) {
    handleTotpChange(raw);
    setQrScannerOpen(false);
  }

  async function handleUploadQrImage() {
    const path = await open({
      multiple: false,
      filters: [{ name: "Image", extensions: ["png", "jpg", "jpeg", "gif", "bmp", "webp"] }],
    });
    if (!path || Array.isArray(path)) return;
    const bytes = await readFile(path);
    const raw = await decodeQrFromImageBytes(bytes);
    if (!raw) {
      setTotpError("No QR code found in that image");
      return;
    }
    handleTotpChange(raw);
  }

  function handleSave() {
    if (!form.totp_secret.trim()) { onSave(form); return; }
    try {
      onSave({ ...form, totp_secret: parseTotpSecret(form.totp_secret) });
    } catch (e) {
      setTotpError(String(e));
    }
  }

  function handleRegenerate(options: PasswordGeneratorOptions) {
    try {
      setGenPreview(generatePassword(options));
      setGenError(null);
    } catch (e) {
      setGenPreview("");
      setGenError(String(e instanceof Error ? e.message : e));
    }
  }

  function handleOpenGenerator() {
    setGenOpen(true);
    handleRegenerate(genOptions);
  }

  function handleToggleCategory(field: keyof Omit<PasswordGeneratorOptions, "length">) {
    const next = { ...genOptions, [field]: !genOptions[field] };
    setGenOptions(next);
    handleRegenerate(next);
  }

  function handleGenLengthChange(length: number) {
    const next = { ...genOptions, length };
    setGenOptions(next);
    handleRegenerate(next);
  }

  function handleUseGeneratedPassword() {
    if (!genPreview) return;
    set("password", genPreview);
    setGenOpen(false);
  }

  function handleGeneratePasskey() {
    const rpId = hostnameOf(form.url, form.site);
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const created = createPasskey({ rpId, challenge, origin: `https://${rpId}` });
    setForm((f) => ({
      ...f,
      passkey: {
        rp_id: rpId,
        credential_id_b64: created.credentialIdB64,
        user_handle_b64: created.userHandleB64,
        private_key_hex: created.privateKeyHex,
        sign_count: created.signCount,
        created_at: created.createdAt,
      },
    }));
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
            <button
              type="button"
              onClick={() => (genOpen ? setGenOpen(false) : handleOpenGenerator())}
              style={{ padding: "0.3em 0.6em", fontSize: "0.9em" }}
              title="Gerar senha"
            >
              🎲
            </button>
          </div>
          <StrengthMeter password={form.password} />
          {genOpen && (
            <div className="card" style={{ marginTop: "0.5rem", padding: "0.75rem" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", flexWrap: "wrap" }}>
                <label style={{ fontSize: "0.82em" }}>
                  Tamanho:{" "}
                  <input
                    type="number"
                    min={1}
                    value={genOptions.length}
                    onChange={(e) => handleGenLengthChange(Math.max(1, Number(e.target.value)))}
                    style={{ width: "4.5rem" }}
                  />
                </label>
                {(
                  [
                    ["uppercase", "Maiúsculas"],
                    ["lowercase", "Minúsculas"],
                    ["numbers", "Números"],
                    ["symbols", "Símbolos"],
                  ] as const
                ).map(([field, label]) => (
                  <button
                    key={field}
                    type="button"
                    onClick={() => handleToggleCategory(field)}
                    style={{
                      padding: "0.25em 0.75em",
                      fontSize: "0.82em",
                      borderColor: genOptions[field] ? "var(--color-accent)" : "var(--color-border)",
                      color: genOptions[field] ? "var(--color-accent)" : "var(--color-text-muted)",
                      background: genOptions[field] ? "rgba(77,208,225,0.1)" : "transparent",
                    }}
                  >
                    {genOptions[field] ? "✓ " : ""}{label}
                  </button>
                ))}
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", marginTop: "0.6rem" }}>
                <code style={{ flex: 1, fontSize: "0.9em", wordBreak: "break-all" }}>
                  {genPreview || "—"}
                </code>
                <button type="button" onClick={() => handleRegenerate(genOptions)} style={{ padding: "0.2em 0.6em", fontSize: "0.8em" }}>
                  🔄 Gerar
                </button>
              </div>
              {genError && <p className="error-text" style={{ margin: "0.4em 0 0", fontSize: "0.82em" }}>{genError}</p>}
              <div className="actions-row" style={{ marginTop: "0.6rem" }}>
                <button type="button" onClick={handleUseGeneratedPassword} disabled={!genPreview}>
                  Usar esta senha
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
      <div className="field">
        <label>Notas</label>
        <input value={form.notes} onChange={(e) => set("notes", e.target.value)} placeholder="notas opcionais" />
      </div>
      <div className="field">
        <label>Grupos</label>
        <ProfilePicker value={form.profiles} onChange={(v) => set("profiles", v)} options={profileOptions} />
      </div>
      <div className="field">
        <label>Segredo 2FA (opcional)</label>
        <div style={{ display: "flex", gap: "0.4rem" }}>
          <input
            style={{ flex: 1 }}
            value={form.totp_secret}
            onChange={(e) => handleTotpChange(e.target.value)}
            placeholder="Segredo base32 ou URI otpauth://..."
          />
          <button
            type="button"
            onClick={() => setQrScannerOpen(true)}
            title="Escanear QR pela webcam"
            style={{ padding: "0.2em 0.6em", fontSize: "0.9em" }}
          >
            📷
          </button>
          <button
            type="button"
            onClick={handleUploadQrImage}
            title="Carregar QR de uma imagem"
            style={{ padding: "0.2em 0.6em", fontSize: "0.9em" }}
          >
            🖼
          </button>
        </div>
        {totpError && <p className="error-text" style={{ margin: "0.25em 0 0", fontSize: "0.82em" }}>{totpError}</p>}
      </div>
      {qrScannerOpen && (
        <TotpQrScanner onDetected={handleQrDetected} onClose={() => setQrScannerOpen(false)} />
      )}
      <div className="field">
        <label>Passkey (opcional)</label>
        {form.passkey ? (
          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
            <span className="muted" style={{ fontSize: "0.85em" }}>
              🔑 {form.passkey.rp_id}
            </span>
            <button type="button" onClick={handleGeneratePasskey} style={{ padding: "0.2em 0.6em", fontSize: "0.8em" }}>
              Recriar
            </button>
          </div>
        ) : (
          <button type="button" onClick={handleGeneratePasskey} style={{ padding: "0.3em 0.8em", fontSize: "0.85em", alignSelf: "flex-start" }}>
            Gerar passkey
          </button>
        )}
      </div>
      <div className="actions-row">
        <button
          onClick={handleSave}
          disabled={saving || !form.site.trim() || !form.username.trim() || !form.password.trim() || !!totpError}
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

  // ── Vault key derivation ──────────────────────────────────────────────────
  const [vaultKeyReady, setVaultKeyReady] = useState<boolean | null>(null);
  const [derivingKey, setDerivingKey] = useState(false);
  const [deriveError, setDeriveError] = useState<string | null>(null);

  const {
    signMessage,
    data: vaultKeySignature,
    isPending: signKeyPending,
    isError: signKeyError,
    error: signKeyErr,
  } = useSignMessage();

  useEffect(() => {
    invoke<boolean>("vault_key_exists").then(setVaultKeyReady).catch(() => setVaultKeyReady(false));
  }, []);

  useEffect(() => {
    if (!vaultKeySignature) return;
    try {
      const { r, s, v } = hexToSignature(vaultKeySignature);
      if (v == null) { setDeriveError("Invalid signature"); setDerivingKey(false); return; }
      invoke("derive_vault_key_from_wallet", { r, s, v: Number(v) })
        .then(() => { setVaultKeyReady(true); setDerivingKey(false); })
        .catch((e: string) => { setDeriveError(String(e)); setDerivingKey(false); });
    } catch (e) {
      setDeriveError(String(e));
      setDerivingKey(false);
    }
  }, [vaultKeySignature]);

  function handleDeriveKey() {
    if (!isConnected) { openConnectModal(); return; }
    setDeriveError(null);
    setDerivingKey(true);
    signMessage({ message: VAULT_KEY_MESSAGE });
  }

  // ── View ──────────────────────────────────────────────────────────────────
  const [view, setView] = useState<"entries" | "settings" | "backup">("entries");

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
  const [permError, setPermError] = useState<string | null>(null);

  // ── Perfis nomeados pelo usuário ─────────────────────────────────────────
  const [profiles, setProfiles] = useState<string[]>([]);
  const [profilesOpen, setProfilesOpen] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [newProfileName, setNewProfileName] = useState("");

  // ── Carregamento inicial ──────────────────────────────────────────────────
  async function loadAll() {
    setLoadingEntries(true);
    try {
      const [e, p, perms, prof] = await Promise.all([
        invoke<VaultEntry[]>("vault_list_entries"),
        invoke<number>("vault_pending_changes"),
        invoke<DeviceVaultPermission[]>("vault_get_device_permissions"),
        invoke<string[]>("vault_list_profiles"),
      ]);
      setEntries(e);
      setPendingCount(p);
      setPermissions(perms);
      setProfiles(prof);
    } catch {
      // sem vault ainda — tudo vazio é ok
    } finally {
      setLoadingEntries(false);
    }
  }

  useEffect(() => { loadAll(); }, []);

  // ── Publicação (vault_publish + on-chain updateVault) — débito #43 ───────
  const {
    hasVault,
    vaultRef,
    publishError,
    pinWarning,
    txErrorMessage,
    buttonLabel,
    buttonDisabled,
    handleEnviar,
    deviceKeyPublishState,
    deviceKeyError,
    handleEnviarViaDeviceKey,
  } = useVaultPublish(pendingCount, () => setPendingCount(0));

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

  // ── Favoritos ────────────────────────────────────────────────────────────
  async function handleToggleFavorite(id: string, favorite: boolean) {
    try {
      await invoke<void>("vault_set_favorite", { id, favorite });
      setEntries((prev) => prev.map((e) => (e.id === id ? { ...e, favorite } : e)));
    } catch (e) {
      setMutateError(String(e));
    }
  }

  // ── Permissões ───────────────────────────────────────────────────────────
  async function handleTogglePerm(pubKey: string, canWrite: boolean) {
    setPermError(null);
    try {
      await invoke<void>("vault_set_device_permission", { pubKey, canWrite });
      setPermissions((prev) => {
        const existing = prev.find((p) => p.pub_key === pubKey);
        if (existing) return prev.map((p) => p.pub_key === pubKey ? { ...p, can_write: canWrite } : p);
        return [...prev, { pub_key: pubKey, can_write: canWrite }];
      });
    } catch (e) {
      setPermError(String(e));
    }
  }

  // ── Gerenciar perfis ─────────────────────────────────────────────────────
  async function handleAddProfile() {
    const name = newProfileName.trim();
    if (!name) return;
    setProfileError(null);
    try {
      await invoke<void>("vault_add_profile", { name });
      setNewProfileName("");
      await loadAll();
    } catch (e) {
      setProfileError(String(e));
    }
  }

  async function handleRenameProfile(oldName: string) {
    const newName = window.prompt(`Renomear perfil "${oldName}" para:`, oldName)?.trim();
    if (!newName || newName === oldName) return;
    setProfileError(null);
    try {
      await invoke<void>("vault_rename_profile", { oldName, newName });
      await loadAll();
    } catch (e) {
      setProfileError(String(e));
    }
  }

  async function handleDeleteProfile(name: string) {
    if (!window.confirm(`Apagar o perfil "${name}"? Ele será removido de todas as senhas que o usam.`)) return;
    setProfileError(null);
    try {
      await invoke<void>("vault_delete_profile", { name });
      await loadAll();
    } catch (e) {
      setProfileError(String(e));
    }
  }

  // ── Ordenação (favoritos primeiro) + filtragem ──────────────────────────────
  // Partição em vez de sort com comparador — preserva a ordem relativa dentro
  // de cada grupo sem depender de garantia de estabilidade de sort.
  const sortedEntries = [...entries.filter((e) => e.favorite), ...entries.filter((e) => !e.favorite)];
  const filtered = filter.trim()
    ? sortedEntries.filter((e) =>
        e.site.toLowerCase().includes(filter.toLowerCase()) ||
        e.username.toLowerCase().includes(filter.toLowerCase()) ||
        e.profiles.some((p) => p.toLowerCase().includes(filter.toLowerCase()))
      )
    : sortedEntries;

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

  // ── View: backup ─────────────────────────────────────────────────────────
  if (view === "backup") {
    return (
      <div>
        <div style={{ display: "flex", alignItems: "center", gap: "1rem", marginBottom: "1rem" }}>
          <button
            onClick={() => setView("entries")}
            style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", padding: "0.3em 0.8em" }}
          >
            ← Vault
          </button>
          <h2 style={{ margin: 0 }}>Backup</h2>
        </div>
        <VaultBackup />
      </div>
    );
  }

  // ── Guard: vault key ─────────────────────────────────────────────────────
  if (vaultKeyReady === null) {
    return <div className="card"><p className="muted">Checking vault key...</p></div>;
  }

  if (!vaultKeyReady) {
    return (
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Unlock Vault</h2>
        <p className="muted" style={{ marginBottom: "1rem", lineHeight: "1.5" }}>
          Your vault key is derived from your wallet signature (RFC 6979).
          Sign once with your Ledger or connected wallet to unlock the vault on this device.
          The key is cached in your OS keyring — you will not need the wallet for daily use.
        </p>
        {(signKeyError || deriveError) && (
          <p className="error-text">
            {signKeyErr?.message?.includes("rejected_by_user")
              ? "Signature rejected on Ledger."
              : `Error: ${deriveError || signKeyErr?.message?.split("\\n")[0] || "operation failed"}`}
          </p>
        )}
        <button
          onClick={handleDeriveKey}
          disabled={derivingKey || signKeyPending}
        >
          {derivingKey || signKeyPending
            ? "Confirm signature on wallet..."
            : !isConnected
            ? "Connect wallet to unlock"
            : "Unlock vault"}
        </button>
      </div>
    );
  }

  // ── View: entries ─────────────────────────────────────────────────────────
  return (
    <div>
      {/* Cabeçalho */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "1rem" }}>
        <h2 style={{ margin: 0 }}>Vault</h2>
        <div style={{ display: "flex", gap: "0.5rem" }}>
          <button
            onClick={() => setView("backup")}
            style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", padding: "0.3em 0.8em", fontSize: "0.85em" }}
          >
            ⏏ Backup
          </button>
          <button
            onClick={() => setView("settings")}
            style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", padding: "0.3em 0.8em", fontSize: "0.85em" }}
          >
            ⚙ Providers
          </button>
        </div>
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
          <div style={{ display: "flex", gap: "0.5rem" }}>
            <button onClick={handleEnviar} disabled={buttonDisabled}>
              {buttonLabel}
            </button>
            {/* Segundo caminho, via device key (sem Ledger) — prova de que o
                pipeline UserOp+bundler funciona no Desktop. Sem UI polida de
                propósito, é validação, não feature acabada pra usuário final
                (ver PROJECT_STATE.md, "Desktop ganha assinatura via device key"). */}
            <button
              onClick={handleEnviarViaDeviceKey}
              disabled={deviceKeyPublishState === "publishing"}
              title="Publica o vault assinando com a device key local, sem toque na Ledger — requer ~/.truthid/bundler_config.json configurado"
            >
              {deviceKeyPublishState === "publishing"
                ? "Publicando via device key..."
                : "Publicar via device key (sem Ledger)"}
            </button>
          </div>
        </div>

        {publishError && (
          <p className="error-text" style={{ marginBottom: 0, marginTop: "0.5rem" }}>
            {publishError}
          </p>
        )}
        {deviceKeyError && (
          <p className="error-text" style={{ marginBottom: 0, marginTop: "0.5rem" }}>
            {deviceKeyError}
          </p>
        )}
        {pinWarning && (
          <p style={{ color: "#d9a441", marginBottom: 0, marginTop: "0.5rem", fontSize: "0.9em" }}>
            ⚠ {pinWarning}
          </p>
        )}
        {txErrorMessage && (
          <p className="error-text" style={{ marginBottom: 0, marginTop: "0.5rem" }}>
            {txErrorMessage}
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
                    initial={{ site: entry.site, url: entry.url, username: entry.username, password: entry.password, notes: entry.notes, profiles: entry.profiles, totp_secret: entry.totp_secret ?? "", passkey: entry.passkey }}
                    onSave={(f) => handleEdit(entry.id, f)}
                    onCancel={() => setEditingId(null)}
                    saving={mutating}
                    profileOptions={profiles}
                  />
                </div>
              );
            }

            return (
              <div key={entry.id} className="card" style={{ padding: "0.75rem 1rem" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", flexWrap: "wrap" }}>
                      <button
                        type="button"
                        onClick={() => handleToggleFavorite(entry.id, !entry.favorite)}
                        title={entry.favorite ? "Remover dos favoritos" : "Adicionar aos favoritos"}
                        style={{
                          padding: "0 0.2em",
                          fontSize: "1em",
                          lineHeight: 1,
                          border: "none",
                          background: "transparent",
                          color: entry.favorite ? "var(--color-accent)" : "var(--color-text-muted)",
                        }}
                      >
                        {entry.favorite ? "★" : "☆"}
                      </button>
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
                    {entry.totp_secret && (
                      <div style={{ marginTop: "0.3rem" }}>
                        <TotpCode secret={entry.totp_secret} />
                      </div>
                    )}
                    {entry.passkey && (
                      <div style={{ marginTop: "0.3rem" }}>
                        <PasskeyBadge passkey={entry.passkey} />
                      </div>
                    )}
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
            profileOptions={profiles}
          />
        </div>
      )}

      <hr />

      {/* Gerenciar perfis */}
      <div style={{ marginBottom: "0.75rem" }}>
        <button
          onClick={() => setProfilesOpen((v) => !v)}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", fontSize: "0.9em", padding: "0.4em 1em" }}
        >
          {profilesOpen ? "▼" : "▶"} Gerenciar perfis ({profiles.length})
        </button>

        {profilesOpen && (
          <div className="card" style={{ marginTop: "0.75rem" }}>
            <p className="muted" style={{ marginTop: 0 }}>
              Crie perfis com o nome que quiser e marque cada senha em quantos perfis fizer sentido.
            </p>
            {profileError && <p className="error-text">{profileError}</p>}
            {profiles.length === 0 ? (
              <p className="muted">Nenhum perfil criado ainda.</p>
            ) : (
              <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", marginBottom: "0.75rem" }}>
                {profiles.map((p) => (
                  <span
                    key={p}
                    className="status-badge"
                    style={{ display: "inline-flex", alignItems: "center", gap: "0.4em", fontSize: "0.85em", padding: "0.2em 0.6em" }}
                  >
                    <button
                      onClick={() => handleRenameProfile(p)}
                      style={{ border: "none", background: "none", padding: 0, font: "inherit", color: "inherit", cursor: "pointer" }}
                      title="Renomear"
                    >
                      {p}
                    </button>
                    <button
                      onClick={() => handleDeleteProfile(p)}
                      style={{ border: "none", background: "none", padding: 0, font: "inherit", color: "var(--color-danger)", cursor: "pointer" }}
                      title="Apagar"
                    >
                      ✕
                    </button>
                  </span>
                ))}
              </div>
            )}
            <div style={{ display: "flex", gap: "0.5rem" }}>
              <input
                value={newProfileName}
                onChange={(e) => setNewProfileName(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") handleAddProfile(); }}
                placeholder="Nome do novo perfil"
                style={{ flex: 1 }}
              />
              <button onClick={handleAddProfile} disabled={!newProfileName.trim()}>
                Adicionar
              </button>
            </div>
          </div>
        )}
      </div>

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
            {permError && <p className="error-text">{permError}</p>}
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

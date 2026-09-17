import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { LanguageSelector } from "./LanguageSelector";
import { MigrateWallet } from "./MigrateWallet";
import { VaultBackup } from "./VaultBackup";
import { BitwardenImport } from "./BitwardenImport";
import { GuardianManagement } from "./GuardianManagement";

type LockPhase = "idle" | "enabling" | "disabling";

// Tela de Configurações (⚙) — reúne o que antes estava espalhado (idioma no
// topbar, migrar wallet no dashboard) mais o bloqueio do app por senha,
// pedido direto do dono do projeto. Backup, import do Bitwarden e Recovery
// (antes uma aba própria / botões no Vault) viraram seções recolhíveis aqui
// — pedido do dono do projeto pra reduzir a poluição visual do Vault e do
// menu principal.
export function Settings({
  onClose,
  onMigrationBusyChange,
  onVaultChanged,
}: {
  onClose: () => void;
  onMigrationBusyChange?: (busy: boolean) => void;
  onVaultChanged?: () => void;
}) {
  const { t } = useTranslation();

  const [lockEnabled, setLockEnabled] = useState<boolean | null>(null);
  const [phase, setPhase] = useState<LockPhase>("idle");
  const [password, setPassword] = useState("");
  const [passwordConfirm, setPasswordConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [backupOpen, setBackupOpen] = useState(false);
  const [bitwardenOpen, setBitwardenOpen] = useState(false);
  const [recoveryOpen, setRecoveryOpen] = useState(false);

  useEffect(() => {
    invoke<boolean>("app_lock_is_enabled").then(setLockEnabled).catch(() => setLockEnabled(false));
  }, []);

  function resetLockForm() {
    setPhase("idle");
    setPassword("");
    setPasswordConfirm("");
    setError(null);
  }

  async function handleEnable() {
    setBusy(true);
    setError(null);
    try {
      await invoke("app_lock_enable", { password });
      setLockEnabled(true);
      resetLockForm();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function handleDisable() {
    setBusy(true);
    setError(null);
    try {
      await invoke("app_lock_disable", { password });
      setLockEnabled(false);
      resetLockForm();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  const enableInvalid = !password.trim() || password !== passwordConfirm;

  return (
    <div>
      <h2 style={{ marginTop: 0 }}>{t("settings.title")}</h2>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("settings.language.title")}</h3>
        <LanguageSelector />
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("settings.wallet.title")}</h3>
        <MigrateWallet onClose={onClose} onBusyChange={onMigrationBusyChange} />
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("settings.appLock.title")}</h3>
        <p className="muted" style={{ lineHeight: "1.5" }}>{t("settings.appLock.explanation")}</p>

        {lockEnabled === null && <p className="muted">{t("settings.appLock.loading")}</p>}

        {lockEnabled === false && phase === "idle" && (
          <button onClick={() => setPhase("enabling")}>{t("settings.appLock.enableButton")}</button>
        )}

        {lockEnabled === true && phase === "idle" && (
          <button onClick={() => setPhase("disabling")}>{t("settings.appLock.disableButton")}</button>
        )}

        {phase === "enabling" && (
          <>
            <div className="field" style={{ marginTop: "0.5rem" }}>
              <label htmlFor="settings-app-lock-new-password">{t("settings.appLock.newPasswordLabel")}</label>
              <input
                id="settings-app-lock-new-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
            </div>
            <div className="field" style={{ marginTop: "0.5rem" }}>
              <label htmlFor="settings-app-lock-confirm-password">{t("settings.appLock.confirmPasswordLabel")}</label>
              <input
                id="settings-app-lock-confirm-password"
                type="password"
                value={passwordConfirm}
                onChange={(e) => setPasswordConfirm(e.target.value)}
                disabled={busy}
              />
            </div>
            {error && <p className="error-text">{error}</p>}
            <div className="actions-row">
              <button onClick={handleEnable} disabled={enableInvalid || busy}>
                {busy ? t("settings.appLock.saving") : t("settings.appLock.confirmEnableButton")}
              </button>
              <button type="button" onClick={resetLockForm} disabled={busy}>
                {t("settings.appLock.cancel")}
              </button>
            </div>
          </>
        )}

        {phase === "disabling" && (
          <>
            <div className="field" style={{ marginTop: "0.5rem" }}>
              <label htmlFor="settings-app-lock-current-password">{t("settings.appLock.currentPasswordLabel")}</label>
              <input
                id="settings-app-lock-current-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
            </div>
            {error && <p className="error-text">{error}</p>}
            <div className="actions-row">
              <button onClick={handleDisable} disabled={!password || busy}>
                {busy ? t("settings.appLock.saving") : t("settings.appLock.confirmDisableButton")}
              </button>
              <button type="button" onClick={resetLockForm} disabled={busy}>
                {t("settings.appLock.cancel")}
              </button>
            </div>
          </>
        )}
      </div>

      {/* Backup, import do Bitwarden e Recovery — recolhidos por padrão, já
          que são usados com pouca frequência (ver comentário no topo). */}
      <div style={{ marginBottom: "0.75rem" }}>
        <button
          onClick={() => setBackupOpen((v) => !v)}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", fontSize: "0.9em", padding: "0.4em 1em" }}
        >
          {backupOpen ? "▼" : "▶"} {t("settings.backup.title")}
        </button>
        {backupOpen && (
          <div style={{ marginTop: "0.75rem" }}>
            <VaultBackup onImported={onVaultChanged} />
          </div>
        )}
      </div>

      <div style={{ marginBottom: "0.75rem" }}>
        <button
          onClick={() => setBitwardenOpen((v) => !v)}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", fontSize: "0.9em", padding: "0.4em 1em" }}
        >
          {bitwardenOpen ? "▼" : "▶"} {t("settings.bitwardenImport.title")}
        </button>
        {bitwardenOpen && (
          <div style={{ marginTop: "0.75rem" }}>
            <BitwardenImport onImported={() => onVaultChanged?.()} />
          </div>
        )}
      </div>

      <div>
        <button
          onClick={() => setRecoveryOpen((v) => !v)}
          style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)", fontSize: "0.9em", padding: "0.4em 1em" }}
        >
          {recoveryOpen ? "▼" : "▶"} {t("settings.recovery.title")}
        </button>
        {recoveryOpen && (
          <div style={{ marginTop: "0.75rem" }}>
            <GuardianManagement />
          </div>
        )}
      </div>
    </div>
  );
}

import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { useVaultBackup } from "../hooks/useVaultBackup";

// Gate de backup OBRIGATÓRIO da wallet local (P78, pedaço 1) — essa chave é
// o único jeito de controlar a identidade até uma eventual migração pra
// outra wallet (pedaço 2, fora de escopo). Perder o device sem backup =
// perder a identidade pra sempre, sem recuperação — decisão do dono do
// projeto de bloquear (não só avisar) até o usuário exportar o backup do
// Vault ou confirmar que já tem um em outro lugar. Deliberadamente sem botão
// de fechar/overlay clicável — diferente dos modais de aprovação
// (PinApprovalModal etc.), este não é dispensável.
//
// Usado em 2 lugares: (1) `inline` dentro do fluxo de criação
// (ConnectLocalWallet.tsx), embutido na tela já em tela cheia; (2) como
// modal bloqueante global em `App.tsx`, caso o app feche antes do usuário
// confirmar (a chave já existe no keyring assim que é gerada).
export function LocalWalletBackupGate({
  onConfirmed,
  inline = false,
}: {
  onConfirmed: () => void;
  inline?: boolean;
}) {
  const { t } = useTranslation();
  const { exportState, exportError, exportBackup } = useVaultBackup();
  const [password, setPassword] = useState("");
  const [passwordConfirm, setPasswordConfirm] = useState("");
  const [alreadyDone, setAlreadyDone] = useState(false);
  const [confirmError, setConfirmError] = useState<string | null>(null);

  const exportInvalid = !password.trim() || password !== passwordConfirm;

  useEffect(() => {
    if (exportState === "done") {
      invoke("confirm_local_wallet_backup").then(onConfirmed).catch((e) => setConfirmError(String(e)));
    }
  }, [exportState, onConfirmed]);

  async function handleExport() {
    await exportBackup(password);
    setPassword("");
    setPasswordConfirm("");
  }

  async function handleConfirmAlreadyDone() {
    setConfirmError(null);
    try {
      await invoke("confirm_local_wallet_backup");
      onConfirmed();
    } catch (e) {
      setConfirmError(String(e));
    }
  }

  const content = (
    <>
      <h2 className={inline ? "local-wallet-connect-title" : "modal-title"}>
        {t("localWalletBackupGate.title")}
      </h2>
      <div className="local-wallet-error-box">{t("localWalletBackupGate.severeWarning")}</div>

      <div className="card" style={{ marginTop: "1rem" }}>
        <h3 style={{ marginTop: 0 }}>{t("localWalletBackupGate.exportSectionTitle")}</h3>
        <div className="field">
          <label>{t("localWalletBackupGate.exportPasswordLabel")}</label>
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        <div className="field" style={{ marginTop: "0.5rem" }}>
          <label>{t("localWalletBackupGate.confirmPasswordLabel")}</label>
          <input
            type="password"
            value={passwordConfirm}
            onChange={(e) => setPasswordConfirm(e.target.value)}
          />
        </div>
        {exportError && <p className="error-text">{exportError}</p>}
        <div className="actions-row">
          <button onClick={handleExport} disabled={exportInvalid || exportState === "exporting"}>
            {exportState === "exporting"
              ? t("localWalletBackupGate.exporting")
              : t("localWalletBackupGate.exportButton")}
          </button>
        </div>
      </div>

      <p className="muted" style={{ textAlign: "center" }}>{t("localWalletBackupGate.orDivider")}</p>

      <div className="card">
        <label style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
          <input
            type="checkbox"
            checked={alreadyDone}
            onChange={(e) => setAlreadyDone(e.target.checked)}
          />
          {t("localWalletBackupGate.alreadyExportedCheckbox")}
        </label>
        {confirmError && <p className="error-text">{confirmError}</p>}
        <div className="actions-row">
          <button onClick={handleConfirmAlreadyDone} disabled={!alreadyDone}>
            {t("localWalletBackupGate.confirmButton")}
          </button>
        </div>
      </div>
    </>
  );

  if (inline) {
    return <div className="local-wallet-connect">{content}</div>;
  }

  return (
    <div className="modal-overlay">
      <div className="modal-box">{content}</div>
    </div>
  );
}

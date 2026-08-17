import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useVaultBackup } from "../hooks/useVaultBackup";

export function VaultBackup() {
  const { t } = useTranslation();
  const { exportState, exportError, exportBackup, importState, importError, importBackup } =
    useVaultBackup();

  const [exportPassword, setExportPassword] = useState("");
  const [exportPasswordConfirm, setExportPasswordConfirm] = useState("");
  const [importPassword, setImportPassword] = useState("");

  const exportInvalid =
    !exportPassword.trim() || exportPassword !== exportPasswordConfirm;

  async function handleExport() {
    await exportBackup(exportPassword);
    setExportPassword("");
    setExportPasswordConfirm("");
  }

  function handleImport() {
    if (!importPassword.trim()) return;
    if (!window.confirm(t("vaultBackup.confirmOverwrite"))) {
      return;
    }
    importBackup(importPassword).then(() => setImportPassword(""));
  }

  return (
    <div>
      <h2>{t("vaultBackup.title")}</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        {t("vaultBackup.descriptionBefore")}
        <code>.truthid-backup</code> {t("vaultBackup.descriptionAfter")}
      </p>

      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h3 style={{ marginTop: 0 }}>{t("vaultBackup.exportTitle")}</h3>
        <div className="field">
          <label>{t("vaultBackup.exportPasswordLabel")}</label>
          <input
            type="password"
            value={exportPassword}
            onChange={(e) => setExportPassword(e.target.value)}
          />
        </div>
        <div className="field" style={{ marginTop: "0.5rem" }}>
          <label>{t("vaultBackup.confirmPasswordLabel")}</label>
          <input
            type="password"
            value={exportPasswordConfirm}
            onChange={(e) => setExportPasswordConfirm(e.target.value)}
          />
        </div>
        {exportError && <p className="error-text">{exportError}</p>}
        {exportState === "done" && <p className="muted">{t("vaultBackup.backupSaved")}</p>}
        <div className="actions-row">
          <button
            onClick={handleExport}
            disabled={exportInvalid || exportState === "exporting"}
          >
            {exportState === "exporting" ? t("vaultBackup.exporting") : t("vaultBackup.exportButton")}
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("vaultBackup.importTitle")}</h3>
        <p className="muted" style={{ marginTop: 0 }}>
          {t("vaultBackup.importDescriptionBefore")} <code>.truthid-backup</code>{" "}
          {t("vaultBackup.importDescriptionAfter")}
        </p>
        <div className="field">
          <label>{t("vaultBackup.backupPasswordLabel")}</label>
          <input
            type="password"
            value={importPassword}
            onChange={(e) => setImportPassword(e.target.value)}
          />
        </div>
        {importError && <p className="error-text">{importError}</p>}
        {importState === "done" && <p className="muted">{t("vaultBackup.backupImported")}</p>}
        <div className="actions-row">
          <button
            onClick={handleImport}
            disabled={!importPassword.trim() || importState === "importing"}
            style={{ borderColor: "var(--color-danger)", color: "var(--color-danger)" }}
          >
            {importState === "importing" ? t("vaultBackup.importing") : t("vaultBackup.importButton")}
          </button>
        </div>
      </div>
    </div>
  );
}

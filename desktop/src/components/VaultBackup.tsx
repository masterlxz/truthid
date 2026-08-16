import { useState } from "react";
import { useVaultBackup } from "../hooks/useVaultBackup";

export function VaultBackup() {
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
    if (
      !window.confirm(
        "This will overwrite the ENTIRE local vault on this device with the contents of the backup file. This cannot be undone. Continue?"
      )
    ) {
      return;
    }
    importBackup(importPassword).then(() => setImportPassword(""));
  }

  return (
    <div>
      <h2>Backup</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        Exports or restores the entire vault (passwords, 2FA, passkeys, profiles) to a
        <code>.truthid-backup</code> file. Encrypted with its own password,
        separate from your wallet — keep this password somewhere safe, it
        cannot be recovered.
      </p>

      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h3 style={{ marginTop: 0 }}>Export</h3>
        <div className="field">
          <label>Export password</label>
          <input
            type="password"
            value={exportPassword}
            onChange={(e) => setExportPassword(e.target.value)}
          />
        </div>
        <div className="field" style={{ marginTop: "0.5rem" }}>
          <label>Confirm password</label>
          <input
            type="password"
            value={exportPasswordConfirm}
            onChange={(e) => setExportPasswordConfirm(e.target.value)}
          />
        </div>
        {exportError && <p className="error-text">{exportError}</p>}
        {exportState === "done" && <p className="muted">Backup saved ✓</p>}
        <div className="actions-row">
          <button
            onClick={handleExport}
            disabled={exportInvalid || exportState === "exporting"}
          >
            {exportState === "exporting" ? "Exporting..." : "Export backup"}
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Import</h3>
        <p className="muted" style={{ marginTop: 0 }}>
          Choose the <code>.truthid-backup</code> file and enter the password used
          at export time.
        </p>
        <div className="field">
          <label>Backup password</label>
          <input
            type="password"
            value={importPassword}
            onChange={(e) => setImportPassword(e.target.value)}
          />
        </div>
        {importError && <p className="error-text">{importError}</p>}
        {importState === "done" && <p className="muted">Backup imported ✓</p>}
        <div className="actions-row">
          <button
            onClick={handleImport}
            disabled={!importPassword.trim() || importState === "importing"}
            style={{ borderColor: "var(--color-danger)", color: "var(--color-danger)" }}
          >
            {importState === "importing" ? "Importing..." : "Choose file and import"}
          </button>
        </div>
      </div>
    </div>
  );
}

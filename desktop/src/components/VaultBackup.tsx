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
        "Isso vai sobrescrever TODO o vault local deste device com o conteúdo do arquivo de backup. Não pode ser desfeito. Continuar?"
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
        Exporta ou restaura o vault inteiro (senhas, 2FA, passkeys, perfis) num
        arquivo <code>.truthid-backup</code>. Cifrado com uma senha própria,
        separada da sua wallet — guarde essa senha em lugar seguro, ela não
        pode ser recuperada.
      </p>

      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h3 style={{ marginTop: 0 }}>Exportar</h3>
        <div className="field">
          <label>Senha de exportação</label>
          <input
            type="password"
            value={exportPassword}
            onChange={(e) => setExportPassword(e.target.value)}
          />
        </div>
        <div className="field" style={{ marginTop: "0.5rem" }}>
          <label>Confirmar senha</label>
          <input
            type="password"
            value={exportPasswordConfirm}
            onChange={(e) => setExportPasswordConfirm(e.target.value)}
          />
        </div>
        {exportError && <p className="error-text">{exportError}</p>}
        {exportState === "done" && <p className="muted">Backup salvo ✓</p>}
        <div className="actions-row">
          <button
            onClick={handleExport}
            disabled={exportInvalid || exportState === "exporting"}
          >
            {exportState === "exporting" ? "Exportando..." : "Exportar backup"}
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Importar</h3>
        <p className="muted" style={{ marginTop: 0 }}>
          Escolha o arquivo <code>.truthid-backup</code> e digite a senha usada
          na exportação.
        </p>
        <div className="field">
          <label>Senha do backup</label>
          <input
            type="password"
            value={importPassword}
            onChange={(e) => setImportPassword(e.target.value)}
          />
        </div>
        {importError && <p className="error-text">{importError}</p>}
        {importState === "done" && <p className="muted">Backup importado ✓</p>}
        <div className="actions-row">
          <button
            onClick={handleImport}
            disabled={!importPassword.trim() || importState === "importing"}
            style={{ borderColor: "var(--color-danger)", color: "var(--color-danger)" }}
          >
            {importState === "importing" ? "Importando..." : "Escolher arquivo e importar"}
          </button>
        </div>
      </div>
    </div>
  );
}

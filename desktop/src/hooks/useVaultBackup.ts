import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { save, open } from "@tauri-apps/plugin-dialog";
import { writeFile, readFile } from "@tauri-apps/plugin-fs";
import { bytesToBase64, base64ToBytes } from "../utils/base64";

// Export/import de um backup criptografado do vault inteiro (senhas, TOTP,
// passkeys, perfis, permissões de device), item 4 do roadmap pós-Fase 14.
// Cifrado com uma senha de exportação separada (PBKDF2+AES-256-GCM, ver
// backup.rs) — não é a vault key derivada da wallet, de propósito: restaurar
// não deve exigir ter a wallet em mãos.
export function useVaultBackup() {
  const [exportState, setExportState] = useState<"idle" | "exporting" | "done" | "error">("idle");
  const [exportError, setExportError] = useState<string | null>(null);
  const [importState, setImportState] = useState<"idle" | "importing" | "done" | "error">("idle");
  const [importError, setImportError] = useState<string | null>(null);

  async function exportBackup(password: string) {
    setExportError(null);
    setExportState("exporting");
    try {
      const path = await save({
        defaultPath: "vault-backup.truthid-backup",
        filters: [{ name: "TruthID Backup", extensions: ["truthid-backup"] }],
      });
      if (!path) {
        setExportState("idle");
        return;
      }
      const blobB64 = await invoke<string>("vault_export_backup", { password });
      await writeFile(path, base64ToBytes(blobB64));
      setExportState("done");
    } catch (e) {
      setExportError(String(e));
      setExportState("error");
    }
  }

  async function importBackup(password: string) {
    setImportError(null);
    setImportState("importing");
    try {
      const path = await open({
        multiple: false,
        filters: [{ name: "TruthID Backup", extensions: ["truthid-backup"] }],
      });
      if (!path || Array.isArray(path)) {
        setImportState("idle");
        return;
      }
      const bytes = await readFile(path);
      await invoke("vault_import_backup", { blobB64: bytesToBase64(bytes), password });
      setImportState("done");
    } catch (e) {
      setImportError(String(e));
      setImportState("error");
    }
  }

  return { exportState, exportError, exportBackup, importState, importError, importBackup };
}

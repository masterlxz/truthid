import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { readFile } from "@tauri-apps/plugin-fs";
import type { BitwardenImportCandidate, BitwardenSkippedItem, VaultEntry } from "../types";

export type DuplicateAction = "skip" | "overwrite" | "new";

export type ImportRow = BitwardenImportCandidate & {
  selected: boolean;
  action: DuplicateAction;
};

type Stage = "idle" | "needs-password" | "reviewing" | "importing" | "done" | "error";

// Import de um export do Bitwarden (JSON, com ou sem senha de export) pro
// Vault. Duas etapas no backend (`bitwarden_import.rs`): decifra (só se o
// arquivo for "password protected") + parse/mapeamento. Escrita local é o
// mesmo `vault_upsert_entry` que add/edit manual já usa — sem publish
// automático, fica pro botão "Enviar" que já existe (`onImported` só
// recarrega a lista/pendingCount).
export function useBitwardenImport(onImported: () => void) {
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState<string | null>(null);
  const [pendingCiphertext, setPendingCiphertext] = useState<string | null>(null);
  const [rows, setRows] = useState<ImportRow[]>([]);
  const [skipped, setSkipped] = useState<BitwardenSkippedItem[]>([]);

  async function pickFile() {
    setError(null);
    try {
      const path = await open({
        multiple: false,
        filters: [{ name: "Bitwarden Export", extensions: ["json"] }],
      });
      if (!path || Array.isArray(path)) {
        return;
      }
      const bytes = await readFile(path);
      const text = new TextDecoder().decode(bytes);
      const parsed = JSON.parse(text) as { encrypted?: boolean; passwordProtected?: boolean };
      if (parsed.encrypted && parsed.passwordProtected) {
        setPendingCiphertext(text);
        setStage("needs-password");
        return;
      }
      await parseAndPreview(text);
    } catch (e) {
      setError(String(e));
      setStage("error");
    }
  }

  async function submitPassword(password: string) {
    if (!pendingCiphertext) return;
    setError(null);
    try {
      const plaintext = await invoke<string>("bitwarden_decrypt_export", {
        data: pendingCiphertext,
        password,
      });
      await parseAndPreview(plaintext);
    } catch (e) {
      setError(String(e));
      // Fica em "needs-password" — deixa tentar de novo sem reler o arquivo.
    }
  }

  async function parseAndPreview(json: string) {
    const preview = await invoke<{
      candidates: BitwardenImportCandidate[];
      skipped: BitwardenSkippedItem[];
    }>("bitwarden_parse_export", { json });
    setRows(
      preview.candidates.map((c) => ({
        ...c,
        selected: true,
        action: c.possible_duplicate_id ? "skip" : "new",
      })),
    );
    setSkipped(preview.skipped);
    setPendingCiphertext(null);
    setStage("reviewing");
  }

  function toggleSelected(index: number) {
    setRows((prev) => prev.map((r, i) => (i === index ? { ...r, selected: !r.selected } : r)));
  }

  function setAction(index: number, action: DuplicateAction) {
    setRows((prev) => prev.map((r, i) => (i === index ? { ...r, action } : r)));
  }

  async function confirmImport() {
    setStage("importing");
    setError(null);
    try {
      for (const row of rows) {
        if (!row.selected) continue;
        // "pular" só faz sentido pra uma duplicata (senão não teria com o
        // que comparar) — não escreve nada, mesmo com o checkbox marcado.
        if (row.possible_duplicate_id && row.action === "skip") continue;
        const { selected: _selected, action, possible_duplicate_id, ...entry } = row;
        const toSave: VaultEntry = {
          ...(entry as VaultEntry),
          id: action === "overwrite" && possible_duplicate_id ? possible_duplicate_id : "",
        };
        await invoke("vault_upsert_entry", { entry: toSave });
      }
      onImported();
      setStage("done");
    } catch (e) {
      setError(String(e));
      setStage("error");
    }
  }

  function reset() {
    setStage("idle");
    setError(null);
    setPendingCiphertext(null);
    setRows([]);
    setSkipped([]);
  }

  return {
    stage,
    error,
    rows,
    skipped,
    pickFile,
    submitPassword,
    toggleSelected,
    setAction,
    confirmImport,
    reset,
  };
}

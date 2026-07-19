import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { Passkey } from "../types";

export interface VaultEditEntryProposal {
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  passkey?: Passkey;
}

export interface IncomingVaultEditRequest {
  id: string;
  entry: VaultEditEntryProposal;
  expiresAtMs: number;
}

/**
 * Escuta propostas de credencial nova vindas da extensão via o canal local
 * (/truthid/v1/vault-edit) — mesmo padrão de useIncomingPinRequest.ts.
 * Diferente do /pin, toda proposta pede aprovação (sem cota/caminho rápido),
 * então este hook dispara pra toda chamada, não só as "novas".
 */
export function useIncomingVaultEditRequest() {
  const [request, setRequest] = useState<IncomingVaultEditRequest | null>(null);

  useEffect(() => {
    invoke<IncomingVaultEditRequest | null>("get_pending_vault_edit_request")
      .then((r) => r && setRequest(r))
      .catch(() => {});

    const unlisten = listen<IncomingVaultEditRequest>("truthid://vault-edit", (event) => {
      setRequest(event.payload);
    });

    return () => {
      unlisten.then((f) => f());
    };
  }, []);

  const clear = useCallback(() => setRequest(null), []);

  return { request, clear };
}

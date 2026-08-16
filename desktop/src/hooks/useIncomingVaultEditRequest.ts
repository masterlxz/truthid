import type { Passkey } from "../types";
import { useIncomingRequest } from "./useIncomingRequest";

export interface VaultEditEntryProposal {
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  passkey?: Passkey;
  pubKey?: string;
  // Preenchido só quando a proposta edita uma VaultEntry já existente (vinda
  // do formulário "Edit" da popup da extensão) — ver VaultEditApprovalModal.
  targetEntryId?: string;
}

// Sync em lote (P29) — uma sessão de aprovação cobre 1+ credenciais
// propostas juntas pela extensão, não mais uma por sessão.
export interface IncomingVaultEditRequest {
  id: string;
  entries: VaultEditEntryProposal[];
  expiresAtMs: number;
  pubKey?: string;
}

export function useIncomingVaultEditRequest() {
  return useIncomingRequest<IncomingVaultEditRequest>(
    "get_pending_vault_edit_request",
    "truthid://vault-edit",
  );
}
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
}

export interface IncomingVaultEditRequest {
  id: string;
  entry: VaultEditEntryProposal;
  expiresAtMs: number;
  pubKey?: string;
}

export function useIncomingVaultEditRequest() {
  return useIncomingRequest<IncomingVaultEditRequest>(
    "get_pending_vault_edit_request",
    "truthid://vault-edit",
  );
}
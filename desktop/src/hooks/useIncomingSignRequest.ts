import type { Address, Hex } from "viem";
import { useIncomingRequest } from "./useIncomingRequest";

export interface IncomingSignRequest {
  id: string;
  appName: string;
  dest: Address;
  value: string;
  callData: Hex;
  functionSignature: string;
  expiresAtMs: number;
}

export function useIncomingSignRequest() {
  return useIncomingRequest<IncomingSignRequest>(
    "get_pending_sign_request",
    "truthid://sign-request",
  );
}
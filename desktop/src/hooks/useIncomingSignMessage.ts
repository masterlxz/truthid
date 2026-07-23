import { useIncomingRequest } from "./useIncomingRequest";

export interface IncomingSignMessage {
  id: string;
  appName: string;
  purpose: string;
  message: string;
  expiresAtMs: number;
}

export function useIncomingSignMessage() {
  return useIncomingRequest<IncomingSignMessage>(
    "get_pending_sign_message",
    "truthid://sign-message",
  );
}
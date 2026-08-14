import { useIncomingRequest } from "./useIncomingRequest";

export interface IncomingPinRequest {
  id: string;
  appName: string;
  expiresAtMs: number;
}

export function useIncomingPinRequest() {
  return useIncomingRequest<IncomingPinRequest>(
    "get_pending_pin_request",
    "truthid://pin",
  );
}
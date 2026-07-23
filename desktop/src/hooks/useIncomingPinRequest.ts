import { useIncomingRequest } from "./useIncomingRequest";

export type PinApprovalReason = "newApp" | "quotaExceeded";

export interface IncomingPinRequest {
  id: string;
  appName: string;
  reason: PinApprovalReason;
  dailyLimit: number;
  expiresAtMs: number;
}

export function useIncomingPinRequest() {
  return useIncomingRequest<IncomingPinRequest>(
    "get_pending_pin_request",
    "truthid://pin",
  );
}
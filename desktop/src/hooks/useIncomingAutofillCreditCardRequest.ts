import { useIncomingRequest } from "./useIncomingRequest";
import type { AutofillCandidate } from "./useIncomingAutofillAddressRequest";
import type { CreditCardData } from "../types";

export interface IncomingAutofillCreditCardRequest {
  id: string;
  candidates: AutofillCandidate<CreditCardData>[];
  expiresAtMs: number;
}

export function useIncomingAutofillCreditCardRequest() {
  return useIncomingRequest<IncomingAutofillCreditCardRequest>(
    "get_pending_autofill_creditcard_request",
    "truthid://autofill-creditcard",
  );
}

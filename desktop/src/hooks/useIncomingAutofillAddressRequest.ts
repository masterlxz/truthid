import { useIncomingRequest } from "./useIncomingRequest";
import type { AddressData } from "../types";

// Reusado por useIncomingAutofillCreditCardRequest.ts — mesmo formato de
// candidato pros dois canais, só o tipo de dado embutido muda.
export interface AutofillCandidate<T> {
  entryId: string;
  data: T;
}

export interface IncomingAutofillAddressRequest {
  id: string;
  candidates: AutofillCandidate<AddressData>[];
  expiresAtMs: number;
}

export function useIncomingAutofillAddressRequest() {
  return useIncomingRequest<IncomingAutofillAddressRequest>(
    "get_pending_autofill_address_request",
    "truthid://autofill-address",
  );
}

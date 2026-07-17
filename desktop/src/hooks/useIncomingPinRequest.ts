import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export type PinApprovalReason = "newApp" | "quotaExceeded";

export interface IncomingPinRequest {
  id: string;
  appName: string;
  reason: PinApprovalReason;
  dailyLimit: number;
  expiresAtMs: number;
}

/**
 * Escuta pedidos de aprovação de pinning vindos de um app terceiro via o
 * canal local (/truthid/v1/pin). Só dispara quando o app precisa de
 * aprovação humana — app novo ou cota diária estourada; um app já
 * autorizado e dentro da cota pina direto no Rust, sem nunca chegar aqui.
 * Mesmo padrão de useIncomingSignMessage.ts: `get_pending_pin_request`
 * cobre o caso da janela estar sem foco no momento exato do evento.
 */
export function useIncomingPinRequest() {
  const [request, setRequest] = useState<IncomingPinRequest | null>(null);

  useEffect(() => {
    invoke<IncomingPinRequest | null>("get_pending_pin_request")
      .then((r) => r && setRequest(r))
      .catch(() => {});

    const unlisten = listen<IncomingPinRequest>("truthid://pin", (event) => {
      setRequest(event.payload);
    });

    return () => {
      unlisten.then((f) => f());
    };
  }, []);

  const clear = useCallback(() => setRequest(null), []);

  return { request, clear };
}

import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export interface IncomingSignMessage {
  id: string;
  appName: string;
  purpose: string;
  message: string;
  expiresAtMs: number;
}

/**
 * Escuta pedidos de assinatura de mensagem (personal_sign) vindos de um app
 * terceiro via o canal local (/truthid/v1/sign-message). Mesmo padrão de
 * useIncomingSignRequest.ts: `get_pending_sign_message` cobre o caso da
 * janela estar sem foco no momento exato do evento, consultado uma vez ao
 * montar, além de escutar o evento em tempo real.
 */
export function useIncomingSignMessage() {
  const [request, setRequest] = useState<IncomingSignMessage | null>(null);

  useEffect(() => {
    invoke<IncomingSignMessage | null>("get_pending_sign_message")
      .then((r) => r && setRequest(r))
      .catch(() => {});

    const unlisten = listen<IncomingSignMessage>("truthid://sign-message", (event) => {
      setRequest(event.payload);
    });

    return () => {
      unlisten.then((f) => f());
    };
  }, []);

  const clear = useCallback(() => setRequest(null), []);

  return { request, clear };
}

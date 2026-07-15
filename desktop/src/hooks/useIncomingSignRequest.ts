import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { Address, Hex } from "viem";

export interface IncomingSignRequest {
  id: string;
  appName: string;
  dest: Address;
  value: string;
  callData: Hex;
  functionSignature: string;
  expiresAtMs: number;
}

/**
 * Escuta pedidos de assinatura vindos de um app terceiro via o canal local
 * (fatia 2b). `get_pending_sign_request` cobre o caso da janela estar sem
 * foco no momento exato do evento `truthid://sign-request` (Rust já teria
 * emitido, mas ninguém escutando ainda) — consultado uma vez ao montar, além
 * de escutar o evento em tempo real.
 */
export function useIncomingSignRequest() {
  const [request, setRequest] = useState<IncomingSignRequest | null>(null);

  useEffect(() => {
    invoke<IncomingSignRequest | null>("get_pending_sign_request")
      .then((r) => r && setRequest(r))
      .catch(() => {});

    const unlisten = listen<IncomingSignRequest>("truthid://sign-request", (event) => {
      setRequest(event.payload);
    });

    return () => {
      unlisten.then((f) => f());
    };
  }, []);

  const clear = useCallback(() => setRequest(null), []);

  return { request, clear };
}

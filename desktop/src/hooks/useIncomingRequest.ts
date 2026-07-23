import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

/**
 * Factory genérica para hooks de "incoming request".
 *
 * Cada canal do local signer server (sign-request, sign-message, pin,
 * vault-edit) segue o mesmo padrão:
 *  1. Consulta o Rust por um pedido pendente ao montar (cobre janela sem foco
 *     no momento exato do evento).
 *  2. Escuta o evento Tauri em tempo real.
 *  3. Expõe `{ request, clear }` — os modais de aprovação consomem isso.
 *
 * Uso:
 *   useIncomingRequest<IncomingSignRequest>("get_pending_sign_request", "truthid://sign-request")
 */
export function useIncomingRequest<T>(cmd: string, event: string) {
  const [request, setRequest] = useState<T | null>(null);

  useEffect(() => {
    invoke<T | null>(cmd)
      .then((r) => r && setRequest(r))
      .catch(() => {});

    const unlisten = listen<T>(event, (eventPayload) => {
      setRequest(eventPayload.payload);
    });

    return () => {
      unlisten.then((f) => f());
    };
  }, [cmd, event]);

  const clear = useCallback(() => setRequest(null), []);

  return { request, clear };
}

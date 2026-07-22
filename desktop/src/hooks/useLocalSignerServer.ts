import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface LocalSignerStatus {
  running: boolean;
  port: number | null;
}

/**
 * Hook que controla o servidor HTTP local (127.0.0.1) que o Desktop expõe
 * pra apps terceiros na mesma máquina se conectarem (fatia 2a). Nesta fatia
 * o servidor só responde ping/handshake — nenhuma assinatura passa por aqui
 * ainda.
 */
export function useLocalSignerServer() {
  const [status, setStatus] = useState<LocalSignerStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isStopping, setIsStopping] = useState(false);

  const refresh = useCallback(() => {
    invoke<LocalSignerStatus>("local_signer_status")
      .then(setStatus)
      .catch((e) => setError(String(e)));
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const start = useCallback(() => {
    setError(null);
    invoke<LocalSignerStatus>("local_signer_start")
      .then(setStatus)
      .catch((e) => setError(String(e)));
  }, []);

  const stop = useCallback(() => {
    setError(null);
    setIsStopping(true);
    invoke<LocalSignerStatus>("local_signer_stop")
      .then(setStatus)
      .catch((e) => setError(String(e)))
      .finally(() => setIsStopping(false));
  }, []);

  return { status, error, start, stop, refresh, isStopping };
}

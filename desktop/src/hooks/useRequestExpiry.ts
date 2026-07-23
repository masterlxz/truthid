import { useEffect, useState } from "react";

/**
 * Hook genérico de expiração para os 4 modais de aprovação.
 *
 * Aceita `expiresAtMs` (timestamp absoluto, em ms) ou `null` (sem pedido
 * pendente). Mantém um `setInterval` de 1s checando se o tempo já passou.
 * Quando expira, para o timer (não fica poluindo o event loop).
 *
 * Uso:
 *   const expired = useRequestExpiry(request?.expiresAtMs ?? null);
 */
export function useRequestExpiry(expiresAtMs: number | null): boolean {
  const [expired, setExpired] = useState(false);

  useEffect(() => {
    if (expiresAtMs === null) {
      setExpired(false);
      return;
    }

    setExpired(Date.now() > expiresAtMs);

    const timer = setInterval(() => {
      if (Date.now() > expiresAtMs) {
        setExpired(true);
        clearInterval(timer);
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [expiresAtMs]);

  return expired;
}
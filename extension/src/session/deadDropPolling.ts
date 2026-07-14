import { computeIpnsName } from './ipnsKey';

const DEFAULT_GATEWAY_URL = 'https://ipfs.io';
const DEFAULT_TIMEOUT_MS = 10_000;

export interface DeadDropPollOptions {
  fetchGateway?: typeof fetch;
  gatewayUrl?: string;
  timeoutMs?: number;
}

/**
 * Uma tentativa de resolver o dead-drop pro `sessionId` dado — quem decide
 * desistir (comparando contra `expiresAt` da sessão) é o chamador
 * (`entrypoints/background.ts`); esta função só faz 1 fetch e devolve os
 * bytes crus ou `null`.
 *
 * O gateway (`ipfs.io`) responde `500`, não `404`, quando o nome IPNS ainda
 * não propagou — trata qualquer resposta não-200 (e qualquer erro de rede)
 * como "ainda não", nunca lança. `cache: 'no-store'` + query de
 * cache-busting evitam que o CDN na frente do gateway sirva uma resposta de
 * "não encontrado" já em cache mesmo depois do registro ter propagado de
 * verdade.
 */
export async function tryFetchDeadDrop(
  sessionId: string,
  options: DeadDropPollOptions = {},
): Promise<Uint8Array | null> {
  const fetchGateway = options.fetchGateway ?? fetch;
  const gatewayUrl = options.gatewayUrl ?? DEFAULT_GATEWAY_URL;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  const ipnsName = computeIpnsName(sessionId);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchGateway(
      `${gatewayUrl}/ipns/${ipnsName}?cachebust=${Date.now()}`,
      { signal: controller.signal, cache: 'no-store' },
    );
    if (!response.ok) return null;
    return new Uint8Array(await response.arrayBuffer());
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

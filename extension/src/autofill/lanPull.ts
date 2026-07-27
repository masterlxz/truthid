import { fetchSessionBlob, getLocalIpsViaChromeApi, subnetHosts } from '../session/lanDiscovery';
import { MOBILE_CANDIDATE_PORTS } from '../vaultEdit/lanDelivery';

const DEFAULT_CONCURRENCY = 50;

export interface LanPullOptions {
  getLocalIps?: () => Promise<string[]>;
  fetchAt?: typeof fetchSessionBlob;
  concurrency?: number;
}

/**
 * Varre o(s) /24 dos IPs locais × `MOBILE_CANDIDATE_PORTS` (48050-48054, o
 * `RemoteSignerLanServer` genérico do Mobile — não o bloco 47850-47854,
 * exclusivo da leitura do vault da 13.9), procurando a resposta cifrada do
 * pedido de autofill. Mesma estratégia de `sweepLan`
 * (`session/lanDiscovery.ts`), mas com a lista de portas certa pra este
 * fluxo — não dá pra reaproveitar `sweepLan` direto porque ele tem
 * `CANDIDATE_PORTS` hardcoded dentro do próprio loop (mesmo padrão que
 * `vaultEdit/lanDelivery.ts::pushToMobile` já usa pro sentido contrário,
 * PUT em vez de GET).
 */
export async function sweepMobileForBlob(
  sessionId: string,
  options: LanPullOptions = {},
): Promise<string | null> {
  const getLocalIps = options.getLocalIps ?? getLocalIpsViaChromeApi;
  const fetchAt = options.fetchAt ?? fetchSessionBlob;
  const concurrency = options.concurrency ?? DEFAULT_CONCURRENCY;

  const localIps = await getLocalIps();
  if (localIps.length === 0) return null;

  const seenHosts = new Set<string>();
  const targets: Array<{ host: string; port: number }> = [];
  for (const ip of localIps) {
    for (const host of subnetHosts(ip)) {
      if (seenHosts.has(host)) continue;
      seenHosts.add(host);
      for (const port of MOBILE_CANDIDATE_PORTS) {
        targets.push({ host, port });
      }
    }
  }

  for (let i = 0; i < targets.length; i += concurrency) {
    const batch = targets.slice(i, i + concurrency);
    const results = await Promise.all(
      batch.map(({ host, port }) => fetchAt(host, port, sessionId)),
    );
    const hit = results.find((r): r is string => r !== null);
    if (hit) return hit;
  }

  return null;
}

/**
 * Fallback de IP manual — tenta um único host em todas as
 * `MOBILE_CANDIDATE_PORTS`, já que o usuário não sabe (nem precisa saber)
 * em qual porta específica o `RemoteSignerLanServer` acabou subindo (a
 * primeira livre da lista).
 */
export async function fetchMobileBlobAt(
  host: string,
  sessionId: string,
  fetchAt: typeof fetchSessionBlob = fetchSessionBlob,
): Promise<string | null> {
  for (const port of MOBILE_CANDIDATE_PORTS) {
    const blob = await fetchAt(host, port, sessionId);
    if (blob) return blob;
  }
  return null;
}

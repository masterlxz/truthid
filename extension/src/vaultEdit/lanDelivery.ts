import { getLocalIpsViaChromeApi, subnetHosts } from '../session/lanDiscovery';

// Portas do `RemoteSignerLanServer` do Mobile — bloco próprio, distinto de
// 47850..47854 (LAN de leitura do vault, `lanDiscovery.ts` acima) e
// 47950..47954 (loopback do Desktop, `desktopDelivery.ts`). Cross-
// referência: `mobile/lib/services/remote_signer_lan_server.dart::
// candidatePorts`.
export const MOBILE_CANDIDATE_PORTS = [48050, 48051, 48052, 48053, 48054];

const DEFAULT_CONCURRENCY = 50;
const DEFAULT_TIMEOUT_MS = 800;

/**
 * PUT `/session/<sessionId>/content` num host:porta — espelha
 * `RemoteSignerLanServer.receiveOnce()` (Dart), que espera exatamente essa
 * rota/verbo e responde 200 assim que recebe o corpo inteiro (não espera a
 * aprovação humana — essa só acontece depois, na tela do celular). Retorna
 * `true` só em 200, nunca lança.
 */
export async function putSessionContent(
  host: string,
  port: number,
  sessionId: string,
  body: Uint8Array,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`http://${host}:${port}/session/${sessionId}/content`, {
      method: 'PUT',
      body: new Blob([body as unknown as BlobPart]),
      signal: controller.signal,
    });
    return response.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export interface LanPushOptions {
  getLocalIps?: () => Promise<string[]>;
  putAt?: typeof putSessionContent;
  concurrency?: number;
}

/**
 * Varre o(s) /24 dos IPs locais × `MOBILE_CANDIDATE_PORTS`, tentando
 * empurrar `body` (já cifrado) pro `RemoteSignerLanServer` do celular —
 * mesma estratégia de `sweepLan` (`session/lanDiscovery.ts`), mas invertida
 * (PUT em vez de GET, sai assim que alguém aceita em vez de assim que
 * alguém devolve algo). Não reaproveita `sweepLan` diretamente porque o
 * contrato de retorno é diferente (bool de sucesso, não um blob).
 */
export async function pushToMobile(
  sessionId: string,
  body: Uint8Array,
  options: LanPushOptions = {},
): Promise<boolean> {
  const getLocalIps = options.getLocalIps ?? getLocalIpsViaChromeApi;
  const putAt = options.putAt ?? putSessionContent;
  const concurrency = options.concurrency ?? DEFAULT_CONCURRENCY;

  const localIps = await getLocalIps();
  if (localIps.length === 0) return false;

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
      batch.map(({ host, port }) => putAt(host, port, sessionId, body)),
    );
    if (results.some((ok) => ok)) return true;
  }

  return false;
}

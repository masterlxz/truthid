/**
 * Descoberta LAN — o ponto de maior risco técnico da 13.9 (fatia 1).
 *
 * Rejeitado: o truque de WebRTC/ICE candidates pra achar o IP local —
 * navegadores modernos ofuscam host candidates atrás de nomes mDNS `.local`
 * por padrão, então esse truque retorna lixo silenciosamente em builds
 * atuais.
 *
 * Mecanismo primário: `chrome.system.network.getNetworkInterfaces()` (só
 * Chrome/Edge — Firefox não implementa essa API, ver `wxt.config.ts`).
 * Fallback (Firefox sempre, Chrome também se o sweep automático não achar
 * nada): IP digitado manualmente pelo usuário (`fetchSessionBlob` direto).
 *
 * Lista de portas espelhada em
 * `mobile/lib/services/vault_lan_server_service.dart` — as duas precisam
 * ficar em sincronia manual.
 */
export const CANDIDATE_PORTS = [47850, 47851, 47852, 47853, 47854];

const DEFAULT_CONCURRENCY = 50;
const DEFAULT_TIMEOUT_MS = 800;

// `@types/chrome` não inclui `chrome.system.network` (só cpu/memory/storage/
// display) — API real, documentada em
// developer.chrome.com/docs/extensions/reference/api/system/network,
// requer a permissão "system.network" (só Chrome/Edge, ver wxt.config.ts).
// Tipada aqui via intersection local em vez de aumentar o namespace global —
// mais simples que brigar com merge de namespace ambiente dotted.
interface ChromeSystemNetworkInterface {
  name: string;
  address: string;
  prefixLength: number;
}

type ChromeWithSystemNetwork = typeof chrome & {
  system: typeof chrome.system & {
    network?: {
      getNetworkInterfaces: (
        callback: (interfaces: ChromeSystemNetworkInterface[]) => void,
      ) => void;
    };
  };
};

export async function fetchSessionBlob(
  host: string,
  port: number,
  sessionId: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<string | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`http://${host}:${port}/session/${sessionId}`, {
      signal: controller.signal,
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { blob?: string };
    return body.blob ?? null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** IPs locais (IPv4) reportados pela API real de extensão — só Chrome/Edge. */
export async function getLocalIpsViaChromeApi(): Promise<string[]> {
  const chromeApi = globalThis.chrome as ChromeWithSystemNetwork | undefined;
  const network = chromeApi?.system?.network;
  if (!network) return [];

  return new Promise((resolve) => {
    network.getNetworkInterfaces((interfaces) => {
      const ipv4 = interfaces
        .map((iface) => iface.address)
        .filter((address) => /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(address));
      resolve(ipv4);
    });
  });
}

/** Todos os hosts do /24 a que `localIp` pertence (ex: 192.168.1.1..254). */
export function subnetHosts(localIp: string): string[] {
  const parts = localIp.split('.');
  if (parts.length !== 4) return [];
  const prefix = parts.slice(0, 3).join('.');
  const hosts: string[] = [];
  for (let i = 1; i <= 254; i++) {
    hosts.push(`${prefix}.${i}`);
  }
  return hosts;
}

export interface SweepOptions {
  getLocalIps?: () => Promise<string[]>;
  fetchAt?: typeof fetchSessionBlob;
  concurrency?: number;
}

/**
 * Varre o(s) /24 dos IPs locais × a lista fixa de portas, em lotes
 * paralelos, e retorna o primeiro blob encontrado (ou `null` se nada bateu).
 * Sai cedo assim que alguém responde — não espera o sweep inteiro terminar.
 */
export async function sweepLan(
  sessionId: string,
  options: SweepOptions = {},
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
      for (const port of CANDIDATE_PORTS) {
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

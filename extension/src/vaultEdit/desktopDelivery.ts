import type { VaultEditProposal } from './pendingEdits';

// Portas candidatas do `local_signer_server.rs` do Desktop — bloco próprio,
// distinto de 47850..47854 (LAN do Mobile/extensão, leitura do vault) e
// 48050..48054 (RemoteSignerLanServer do Mobile, canal cross-device). Igual
// ao resto do projeto, duplicado aqui porque não há pacote compartilhado
// entre extensão e Desktop — cross-referência: `desktop/src-tauri/src/
// local_signer_server.rs::CANDIDATE_PORTS`.
export const DESKTOP_CANDIDATE_PORTS = [47950, 47951, 47952, 47953, 47954];

const PING_TIMEOUT_MS = 800;
// Mesmo valor de `vault_edit::VAULT_EDIT_REQUEST_TIMEOUT` — o POST fica
// pendurado esperando a decisão humana no Desktop, então o timeout do lado
// da extensão precisa ser generoso o bastante pra nunca desistir antes do
// Rust (senão a extensão mostraria erro num pedido que na verdade ainda
// está esperando aprovação).
const VAULT_EDIT_TIMEOUT_MS = 300_000;

export type DesktopDeliveryStatus =
  | 'approved'
  | 'rejected'
  | 'timeout'
  | 'busy'
  | 'invalid'
  | 'not-found'
  | 'error';

export interface DesktopDeliveryResult {
  status: DesktopDeliveryStatus;
  id?: string;
  error?: string;
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Confirma que há um TruthID Desktop escutando numa das portas candidatas,
 * via o endpoint `/truthid/v1/ping` que já existe (usado hoje pelo
 * handshake de apps terceiros) — evita mandar o POST de verdade (que
 * segura a conexão por até 5min esperando aprovação humana) pra uma porta
 * que não é o Desktop.
 */
export async function findDesktopPort(
  ports: number[] = DESKTOP_CANDIDATE_PORTS,
): Promise<number | null> {
  for (const port of ports) {
    try {
      const resp = await fetchWithTimeout(
        `http://127.0.0.1:${port}/truthid/v1/ping`,
        {},
        PING_TIMEOUT_MS,
      );
      if (!resp.ok) continue;
      const body = (await resp.json()) as { service?: string };
      if (body.service === 'truthid-desktop') return port;
    } catch {
      // Porta fechada, timeout, ou não é o TruthID — tenta a próxima.
    }
  }
  return null;
}

/**
 * Envia uma proposta pro `/truthid/v1/vault-edit` do Desktop na mesma
 * máquina. Não usa QR nem cifra — loopback já implica mesmo processo de
 * usuário, mesmo nível de confiança de `/truthid/v1/pin`.
 */
export async function sendToDesktop(
  proposal: Omit<VaultEditProposal, 'id' | 'createdAtMs'>,
  ports: number[] = DESKTOP_CANDIDATE_PORTS,
): Promise<DesktopDeliveryResult> {
  const port = await findDesktopPort(ports);
  if (port === null) return { status: 'not-found' };

  try {
    const resp = await fetchWithTimeout(
      `http://127.0.0.1:${port}/truthid/v1/vault-edit`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(proposal),
      },
      VAULT_EDIT_TIMEOUT_MS,
    );
    const body = (await resp.json()) as { status: DesktopDeliveryStatus; id?: string; error?: string };
    return body;
  } catch (e) {
    return { status: 'error', error: String(e) };
  }
}

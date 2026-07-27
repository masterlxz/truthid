import {
  DESKTOP_CANDIDATE_PORTS,
  fetchWithTimeout,
  findDesktopPort,
} from '../vaultEdit/desktopDelivery';
import type { DecryptedAddress } from './addressFill';
import type { DecryptedCreditCard } from './creditCardFill';

/**
 * Terceira tentativa de entrega do autofill (Fase 15.4, fatia 2 — Desktop),
 * ao lado do LAN (`lanPull.ts`) e do dead-drop (`deadDropPull.ts`): se o
 * TruthID Desktop estiver rodando na mesma máquina que o navegador, ele
 * também pode responder — sem QR, sem cifra (loopback já é o mesmo nível de
 * confiança do `/pin`/`/vault-edit`, ver `local_signer_server.rs`). Mesmo
 * bloco de portas (`DESKTOP_CANDIDATE_PORTS`, 47950-54) e mesmo
 * `findDesktopPort`/`fetchWithTimeout` que `vaultEdit/desktopDelivery.ts` já
 * usa pra falar com o mesmo servidor multiplexado.
 */
const AUTOFILL_DESKTOP_TIMEOUT_MS = 300_000;

export type AutofillDesktopStatus =
  | 'filled'
  | 'no-addresses'
  | 'no-cards'
  | 'rejected'
  | 'timeout'
  | 'busy'
  | 'invalid'
  | 'not-found'
  | 'error';

export interface AutofillAddressDesktopResult {
  status: AutofillDesktopStatus;
  address?: DecryptedAddress;
  error?: string;
}

export interface AutofillCreditCardDesktopResult {
  status: AutofillDesktopStatus;
  card?: DecryptedCreditCard;
  error?: string;
}

export async function fetchAddressFromDesktop(
  ports: number[] = DESKTOP_CANDIDATE_PORTS,
): Promise<AutofillAddressDesktopResult> {
  const port = await findDesktopPort(ports);
  if (port === null) return { status: 'not-found' };

  try {
    const resp = await fetchWithTimeout(
      `http://127.0.0.1:${port}/truthid/v1/autofill-address`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' },
      AUTOFILL_DESKTOP_TIMEOUT_MS,
    );
    return (await resp.json()) as AutofillAddressDesktopResult;
  } catch (e) {
    return { status: 'error', error: String(e) };
  }
}

export async function fetchCreditCardFromDesktop(
  ports: number[] = DESKTOP_CANDIDATE_PORTS,
): Promise<AutofillCreditCardDesktopResult> {
  const port = await findDesktopPort(ports);
  if (port === null) return { status: 'not-found' };

  try {
    const resp = await fetchWithTimeout(
      `http://127.0.0.1:${port}/truthid/v1/autofill-creditcard`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' },
      AUTOFILL_DESKTOP_TIMEOUT_MS,
    );
    return (await resp.json()) as AutofillCreditCardDesktopResult;
  } catch (e) {
    return { status: 'error', error: String(e) };
  }
}

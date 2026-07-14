/**
 * Schema v1 do QR de sessão do Vault (13.9, fatia 1 — só transporte LAN).
 *
 * `sessionId` funciona como path HTTP *e* como bearer token — não há campo
 * separado de "discoveryToken", já é imprevisível o bastante (16 bytes
 * aleatórios). `expiresAt` é timestamp absoluto (unix ms), não relativo —
 * evita ambiguidade de clock-skew entre celular e computador.
 *
 * Espelha a validação em `mobile/lib/screens/vault_session_screen.dart`
 * (`_validatePayload`) — qualquer mudança de schema precisa dos dois lados.
 */
export interface VaultSessionQrPayload {
  action: 'truthid-vault-session';
  v: 1;
  sessionId: string;
  ephemeralPubKey: string; // 0x + 33 bytes SEC1 comprimido, hex
  expiresAt: number; // unix ms, absoluto
}

export const SESSION_TTL_MS = 3 * 60 * 1000;

export function buildQrPayload(
  sessionId: string,
  ephemeralPubKeyHex: string,
  now: number = Date.now(),
): VaultSessionQrPayload {
  return toQrPayload(sessionId, ephemeralPubKeyHex, now + SESSION_TTL_MS);
}

/** Reconstrói o payload do QR a partir de um estado já existente (ex: popup
 * reaberta antes do TTL expirar) — reusa o mesmo `expiresAt`, não gera um
 * novo TTL a cada reabertura. */
export function toQrPayload(
  sessionId: string,
  ephemeralPubKeyHex: string,
  expiresAt: number,
): VaultSessionQrPayload {
  return {
    action: 'truthid-vault-session',
    v: 1,
    sessionId,
    ephemeralPubKey: ephemeralPubKeyHex,
    expiresAt,
  };
}

export function randomSessionId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

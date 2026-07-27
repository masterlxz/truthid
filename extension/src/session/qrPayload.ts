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

/**
 * Schema v1 do QR de proposta de credencial nova (Sessão 134, item 6 do
 * roadmap) — a extensão vira "requisitante" pela primeira vez, mesmo schema
 * já validado pelo `/truthid/v1/pin` cross-device (`ephemeralPubKey` é da
 * extensão agora, não do Device; espelha `pin_approval_screen.dart`'s
 * `_validatePayload`, que já aceita exatamente esses 5 campos). `appName`
 * fixo — só a própria extensão TruthID fala esse protocolo.
 */
export interface VaultEditQrPayload {
  action: 'truthid-vault-edit';
  v: 1;
  sessionId: string;
  ephemeralPubKey: string; // 0x + 33 bytes SEC1 comprimido, hex
  expiresAt: number; // unix ms, absoluto
  appName: 'TruthID Extension';
}

export const VAULT_EDIT_QR_TTL_MS = 3 * 60 * 1000;

export function buildVaultEditQrPayload(
  sessionId: string,
  ephemeralPubKeyHex: string,
  now: number = Date.now(),
): VaultEditQrPayload {
  return {
    action: 'truthid-vault-edit',
    v: 1,
    sessionId,
    ephemeralPubKey: ephemeralPubKeyHex,
    expiresAt: now + VAULT_EDIT_QR_TTL_MS,
    appName: 'TruthID Extension',
  };
}

/**
 * Schema v1 do QR de pedido de autofill de endereço (Fase 15.4, fatia 1 — só
 * endereço, só transporte LAN). Mesmo esqueleto de 5 campos que
 * `VaultEditQrPayload` já usa — a extensão é quem gera o par efêmero aqui
 * (ela é a "requisitante", como no `/truthid/v1/pin`), o Device decifra a
 * resposta com a chave pública anunciada e entrega via
 * `RemoteSignerLanServer` (mesmo servidor genérico de sign-message/pin,
 * portas 48050-48054 — não o bloco 47850-47854, que é exclusivo da leitura
 * do vault da 13.9). Espelha a validação em
 * `mobile/lib/screens/autofill_address_approval_screen.dart`.
 */
export interface AutofillAddressQrPayload {
  action: 'truthid-autofill-address';
  v: 1;
  sessionId: string;
  ephemeralPubKey: string; // 0x + 33 bytes SEC1 comprimido, hex
  expiresAt: number; // unix ms, absoluto
  appName: 'TruthID Extension';
}

export const AUTOFILL_ADDRESS_QR_TTL_MS = 3 * 60 * 1000;

export function buildAutofillAddressQrPayload(
  sessionId: string,
  ephemeralPubKeyHex: string,
  now: number = Date.now(),
): AutofillAddressQrPayload {
  return {
    action: 'truthid-autofill-address',
    v: 1,
    sessionId,
    ephemeralPubKey: ephemeralPubKeyHex,
    expiresAt: now + AUTOFILL_ADDRESS_QR_TTL_MS,
    appName: 'TruthID Extension',
  };
}

/**
 * Schema v1 do QR de pedido de autofill de cartão de crédito (Fase 15.4,
 * fatia 2 — mesmo recorte de transporte da fatia 1: só LAN, só Mobile
 * responde). Mesmo esqueleto de 5 campos que `AutofillAddressQrPayload` já
 * usa — só o `action` muda, pra o Mobile rotear pra
 * `AutofillCreditCardApprovalScreen` em vez de
 * `AutofillAddressApprovalScreen` (o restante do transporte — LAN sweep,
 * fetch manual por IP — já era genérico o bastante pra servir aos dois,
 * ver `autofill/messages.ts`).
 */
export interface AutofillCreditCardQrPayload {
  action: 'truthid-autofill-creditcard';
  v: 1;
  sessionId: string;
  ephemeralPubKey: string; // 0x + 33 bytes SEC1 comprimido, hex
  expiresAt: number; // unix ms, absoluto
  appName: 'TruthID Extension';
}

export const AUTOFILL_CREDITCARD_QR_TTL_MS = 3 * 60 * 1000;

export function buildAutofillCreditCardQrPayload(
  sessionId: string,
  ephemeralPubKeyHex: string,
  now: number = Date.now(),
): AutofillCreditCardQrPayload {
  return {
    action: 'truthid-autofill-creditcard',
    v: 1,
    sessionId,
    ephemeralPubKey: ephemeralPubKeyHex,
    expiresAt: now + AUTOFILL_CREDITCARD_QR_TTL_MS,
    appName: 'TruthID Extension',
  };
}

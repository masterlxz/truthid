/**
 * Estado da sessão persistido em `chrome.storage.session` (não em memória de
 * módulo — service workers MV3 são suspensos e perdem variáveis de módulo;
 * `chrome.storage.session` é em-memória mas sobrevive a isso, e nunca é
 * escrito em disco). Cobre desde a geração do QR até a chegada (ou
 * expiração) das entradas.
 */
export type SessionStatus =
  | 'showingQr'
  | 'discovering'
  | 'received'
  | 'expired'
  | 'error';

// Intencionalmente sem `totp_secret`/`passkey`: 2FA e passkeys ficam isolados
// no Device (Mobile ou Desktop), nunca na extensão — o Mobile já filtra esses
// campos antes de cifrar/enviar (ver `VaultEntry.toJsonForExtension()` em
// vault_repository.dart). Não adicionar nenhum dos dois campos aqui.
export interface VaultEntry {
  id: string;
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  profiles: string[];
}

export interface SessionState {
  status: SessionStatus;
  sessionId: string;
  ephemeralPrivateKeyHex: string;
  ephemeralPublicKeyHex: string; // 0x + 33 bytes comprimida, hex
  expiresAt: number; // unix ms
  entries?: VaultEntry[];
  errorMessage?: string;
}

export function isExpired(state: Pick<SessionState, 'expiresAt'>, now = Date.now()): boolean {
  return state.expiresAt <= now;
}

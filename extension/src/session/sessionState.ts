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

// Espelho de `Passkey` em `desktop/src/types.ts`/`mobile/lib/services/
// vault_repository.dart` — chave privada em hex cru, mesmo shape dos outros
// dois lados. A extensão precisa dela pra assinar `navigator.credentials.get`
// em sites reais (ver `../webauthn.ts`), ao contrário do `totp_secret`
// (comentário abaixo), que continua isolado no Device — 2FA nunca passa pela
// extensão, decisão de segurança separada e deliberada.
export interface Passkey {
  rp_id: string;
  credential_id_b64: string;
  user_handle_b64: string;
  private_key_hex: string;
  sign_count: number;
  created_at: number;
}

// Intencionalmente sem `totp_secret`: 2FA fica isolado no Device (Mobile ou
// Desktop), nunca na extensão — o Mobile já filtra esse campo antes de
// cifrar/enviar (ver `VaultEntry.toJsonForExtension()` em
// vault_repository.dart). `passkey` passou a ser incluído na Sessão 132 —
// não remover o comentário de `totp_secret` nem adicionar esse campo aqui.
export interface VaultEntry {
  id: string;
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  profiles: string[];
  passkey?: Passkey;
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

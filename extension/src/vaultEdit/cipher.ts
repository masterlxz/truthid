import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';

import { hexToBytes } from '../util/bytes';

/**
 * Cifra simétrica do payload entregue pro celular na fase 1 do
 * `/truthid/v1/vault-edit` cross-device (Sessão 134) — mesma técnica de
 * `mobile/lib/services/pin_content_cipher_service.dart` (chave AES-256
 * derivada via HKDF do `sessionId`, já conhecido só por quem viu o QR — não
 * precisa de troca de chave pública nesta direção, igual ao `/pin`).
 *
 * Salt/info **diferentes** dos usados pelo `/pin` — nunca reusar a mesma
 * derivação entre protocolos (domain separation, mesmo cuidado já
 * documentado no arquivo Dart original).
 */
const HKDF_SALT = 'TruthID Vault Edit Content';
const HKDF_INFO = 'content-key-v1';
const NONCE_LEN = 12;

export function deriveVaultEditContentKey(sessionIdHex: string): Uint8Array {
  const sessionIdBytes = hexToBytes(sessionIdHex);
  return hkdf(sha256, sessionIdBytes, new TextEncoder().encode(HKDF_SALT), new TextEncoder().encode(HKDF_INFO), 32);
}

/** Formato: `nonce(12) || ciphertext+tag` (Web Crypto's AES-GCM produz essa concatenação). */
export async function encryptVaultEditContent(
  plaintext: Uint8Array,
  key: Uint8Array,
): Promise<Uint8Array> {
  const aesKey = await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt']);
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LEN));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, plaintext),
  );

  const blob = new Uint8Array(NONCE_LEN + ciphertext.length);
  blob.set(nonce, 0);
  blob.set(ciphertext, NONCE_LEN);
  return blob;
}

export async function decryptVaultEditContent(
  blob: Uint8Array,
  key: Uint8Array,
): Promise<Uint8Array> {
  if (blob.length < NONCE_LEN + 16) {
    throw new Error('vault edit content blob too short or corrupted');
  }
  const aesKey = await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['decrypt']);
  const nonce = blob.slice(0, NONCE_LEN);
  const ciphertext = blob.slice(NONCE_LEN);
  const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aesKey, ciphertext);
  return new Uint8Array(plaintext);
}

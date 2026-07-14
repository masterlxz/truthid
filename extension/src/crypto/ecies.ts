import { secp256k1 } from '@noble/curves/secp256k1';
import { sha256 } from '@noble/hashes/sha256';

/**
 * ECIES genérico (secp256k1 ECDH + SHA-256 + AES-256-GCM) — espelha
 * `encrypt_bytes_for_device` em `desktop/src-tauri/src/lib.rs` e
 * `mobile/lib/services/ecies_service.dart` byte-a-byte.
 *
 * Formato do blob: ephemeral_pubkey(33 bytes comprimida) || nonce(12 bytes)
 * || ciphertext+tag (Web Crypto's AES-GCM produz/espera exatamente essa
 * concatenação, sem precisar separar o tag manualmente).
 *
 * Risco de interop concreto (não só teórico — é a razão do teste de vetor
 * fixo em `ecies.test.ts`): `secp256k1.getSharedSecret` retorna o ponto EC
 * comprimido inteiro (1 byte de prefixo `0x02`/`0x03` + 32 bytes de X) —
 * tem que descartar esse byte de prefixo antes de fazer o hash, senão a
 * chave AES diverge silenciosamente da que Rust/Dart calculam (mesma classe
 * dos 2 bugs de ECIES já documentados neste projeto: a falta do SHA-256 do
 * segredo ECDH, achada na Sessão 92, e o prefixo `0x04` esquecido em
 * `device_key_service.dart`).
 */

const EPHEMERAL_PUBKEY_LEN = 33;
const NONCE_LEN = 12;

export async function encrypt(
  plaintext: Uint8Array,
  recipientPubKeyHex: string,
): Promise<Uint8Array> {
  const recipientPubKey = hexToBytes(normalizeHex(recipientPubKeyHex));

  const ephemeralPrivKey = secp256k1.utils.randomPrivateKey();
  const ephemeralPubKey = secp256k1.getPublicKey(ephemeralPrivKey, true);

  const aesKey = await deriveAesKey(ephemeralPrivKey, recipientPubKey);

  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LEN));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, plaintext),
  );

  const blob = new Uint8Array(EPHEMERAL_PUBKEY_LEN + NONCE_LEN + ciphertext.length);
  blob.set(ephemeralPubKey, 0);
  blob.set(nonce, EPHEMERAL_PUBKEY_LEN);
  blob.set(ciphertext, EPHEMERAL_PUBKEY_LEN + NONCE_LEN);
  return blob;
}

export async function decrypt(
  blob: Uint8Array,
  recipientPrivKey: Uint8Array,
): Promise<Uint8Array> {
  if (blob.length < EPHEMERAL_PUBKEY_LEN + NONCE_LEN + 16) {
    throw new Error('blob too short to be a valid ECIES payload');
  }

  const ephemeralPubKey = blob.slice(0, EPHEMERAL_PUBKEY_LEN);
  const nonce = blob.slice(EPHEMERAL_PUBKEY_LEN, EPHEMERAL_PUBKEY_LEN + NONCE_LEN);
  const ciphertext = blob.slice(EPHEMERAL_PUBKEY_LEN + NONCE_LEN);

  const aesKey = await deriveAesKey(recipientPrivKey, ephemeralPubKey);

  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce },
    aesKey,
    ciphertext,
  );
  return new Uint8Array(plaintext);
}

async function deriveAesKey(
  selfPrivKey: Uint8Array,
  otherPubKey: Uint8Array,
): Promise<CryptoKey> {
  const sharedPoint = secp256k1.getSharedSecret(selfPrivKey, otherPubKey, true);
  // Descarta o byte de prefixo 0x02/0x03 — só o X coordinate (32 bytes) é o
  // "segredo compartilhado" que Rust (`raw_secret_bytes()`) e Dart
  // (`computeSecret`) calculam.
  const sharedX = sharedPoint.slice(1);
  const aesKeyBytes = sha256(sharedX);
  return crypto.subtle.importKey('raw', aesKeyBytes, 'AES-GCM', false, [
    'encrypt',
    'decrypt',
  ]);
}

function normalizeHex(hex: string): string {
  return hex.startsWith('0x') ? hex.slice(2) : hex;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

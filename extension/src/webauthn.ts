import { p256 } from '@noble/curves/p256';
import { sha256 } from '@noble/hashes/sha256';

import { hexToBytes } from './util/bytes';

/**
 * Assinatura de asserção WebAuthn (login com passkey já existente) — porte
 * de `desktop/src/utils/webauthn.ts` (Sessão 124-125, "Testar assinatura"),
 * só a metade de `get()`. Mesmo padrão de duplicação por plataforma do
 * resto do projeto (ver `crypto/ecies.ts`): reimplementado aqui, nunca
 * importado direto do Desktop (não há pacote compartilhado). `createPasskey`/
 * `buildAttestationObject`/CBOR (só usados no registro, `create()`) ficam de
 * fora de propósito — Sessão 132 só cobre login, ver PROJECT_STATE.md.
 */

const AAGUID = new Uint8Array(16); // zeros — sem attestation de hardware real, igual ao Desktop.

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Decodifica de volta pra bytes o `credential_id_b64`/`user_handle_b64` já
// sincronizados (o Desktop só gera/exibe essas strings, nunca precisou
// decodificar — a extensão precisa pra montar o `rawId`/`userHandle` reais
// do objeto de resposta que a página espera).
export function base64UrlDecode(b64url: string): Uint8Array {
  const padded = b64url.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(b64url.length / 4) * 4, '=');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, c) => sum + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

/**
 * Monta o `authenticatorData` (§6.1 da spec): rpIdHash(32) || flags(1) ||
 * signCount(4, BE) — sem `attestedCredentialData` (só usado no registro).
 * Flags sempre 0x05 (UP+UV) — autenticador virtual, sem presença/biometria
 * real (mesma simplificação já aceita no Desktop/Mobile).
 */
export function buildAuthenticatorData(params: { rpId: string; signCount: number }): Uint8Array {
  const rpIdHash = sha256(new TextEncoder().encode(params.rpId));
  const signCountBytes = new Uint8Array(4);
  new DataView(signCountBytes.buffer).setUint32(0, params.signCount, false);
  return concatBytes(rpIdHash, new Uint8Array([0x05]), signCountBytes);
}

export type SignedAssertion = {
  authenticatorData: Uint8Array;
  clientDataJSON: string;
  signatureDer: Uint8Array;
  newSignCount: number;
};

/**
 * Assina `authenticatorData || SHA-256(clientDataJSON)` com ES256 (§6.3.3) —
 * idêntico ao Desktop, incluindo o `lowS: true` explícito (ver comentário
 * abaixo). `extension/src/webauthn.test.ts` prova saída byte-a-byte igual ao
 * vetor fixo já validado cross-plataforma (TS↔Dart) na Sessão 124-125.
 */
export function signAssertion(params: {
  privateKeyHex: string;
  rpId: string;
  signCount: number;
  challenge: Uint8Array;
  origin: string;
}): SignedAssertion {
  const newSignCount = params.signCount + 1;
  const authenticatorData = buildAuthenticatorData({ rpId: params.rpId, signCount: newSignCount });

  const clientDataJSON = JSON.stringify({
    type: 'webauthn.get',
    challenge: base64UrlEncode(params.challenge),
    origin: params.origin,
  });
  const clientDataHash = sha256(new TextEncoder().encode(clientDataJSON));
  const message = concatBytes(authenticatorData, clientDataHash);

  const privateKey = hexToBytes(params.privateKeyHex);
  // Explícito mesmo a doc dizendo que é o padrão — não é, na versão
  // instalada de @noble/curves (mesmo achado do Desktop, webauthn.ts). Sem
  // isso o vetor cruzado bateria em tudo menos no `s` da assinatura (par
  // low-S/high-S).
  const signature = p256.sign(sha256(message), privateKey, { lowS: true });

  return {
    authenticatorData,
    clientDataJSON,
    signatureDer: signature.toDERRawBytes(),
    newSignCount,
  };
}

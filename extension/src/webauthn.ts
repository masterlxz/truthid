import { p256 } from '@noble/curves/p256';
import { sha256 } from '@noble/hashes/sha256';

import { bytesToHex, hexToBytes } from './util/bytes';
import { encodeBytes, encodeInt, encodeMap, encodeText } from './cbor';

/**
 * WebAuthn (P-256/ES256) — porte de `desktop/src/utils/webauthn.ts`. Mesmo
 * padrão de duplicação por plataforma do resto do projeto (ver
 * `crypto/ecies.ts`): reimplementado aqui, nunca importado direto do
 * Desktop (não há pacote compartilhado). Sessão 132 portou só `get()`
 * (login); Sessão 134 completa com `createPasskey`/`buildAttestationObject`
 * (registro via `navigator.credentials.create()`, item 6 do roadmap).
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

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

/**
 * Encodes a P-256 public key as a COSE_Key CBOR map, per WebAuthn §6.5.1.1 —
 * mesma ordem de chaves do Desktop (não CBOR canonical sort).
 */
export function encodeCoseP256PublicKey(x: Uint8Array, y: Uint8Array): Uint8Array {
  return encodeMap([
    [encodeInt(1), encodeInt(2)],
    [encodeInt(3), encodeInt(-7)],
    [encodeInt(-1), encodeInt(1)],
    [encodeInt(-2), encodeBytes(x)],
    [encodeInt(-3), encodeBytes(y)],
  ]);
}

type AttestedCredential = {
  credentialId: Uint8Array;
  coseP256PublicKey: Uint8Array;
};

/**
 * Monta o `authenticatorData` (§6.1 da spec): rpIdHash(32) || flags(1) ||
 * signCount(4, BE) || [attestedCredentialData]. Flags sempre inclui UP+UV
 * (0x05) — autenticador virtual, sem presença/biometria real (mesma
 * simplificação já aceita no Desktop/Mobile); bit AT (0x40) somado quando
 * `attestedCredential` presente (só no registro).
 */
export function buildAuthenticatorData(params: {
  rpId: string;
  signCount: number;
  attestedCredential?: AttestedCredential;
}): Uint8Array {
  const rpIdHash = sha256(new TextEncoder().encode(params.rpId));
  const flags = params.attestedCredential ? 0x45 : 0x05;
  const signCountBytes = new Uint8Array(4);
  new DataView(signCountBytes.buffer).setUint32(0, params.signCount, false);

  if (!params.attestedCredential) {
    return concatBytes(rpIdHash, new Uint8Array([flags]), signCountBytes);
  }

  const { credentialId, coseP256PublicKey } = params.attestedCredential;
  const credentialIdLen = new Uint8Array(2);
  new DataView(credentialIdLen.buffer).setUint16(0, credentialId.length, false);

  return concatBytes(
    rpIdHash,
    new Uint8Array([flags]),
    signCountBytes,
    AAGUID,
    credentialIdLen,
    credentialId,
    coseP256PublicKey,
  );
}

/** Builds a "none"-format WebAuthn attestationObject CBOR map (§6.5.4). */
export function buildAttestationObject(authData: Uint8Array): Uint8Array {
  return encodeMap([
    [encodeText('fmt'), encodeText('none')],
    [encodeText('attStmt'), encodeMap([])],
    [encodeText('authData'), encodeBytes(authData)],
  ]);
}

export type CreatedPasskey = {
  privateKeyHex: string;
  credentialIdB64: string;
  userHandleB64: string;
  clientDataJSON: string;
  attestationObject: Uint8Array;
  signCount: number;
  createdAt: number;
};

/**
 * Gera um par de chaves P-256 novo e monta authenticatorData +
 * attestationObject "none" — cerimônia de registro completa, local e
 * self-contida, idêntica ao `createPasskey` do Desktop. Chave privada nunca
 * sai do processo da extensão até o Device aprovar (ver
 * `vaultEdit/pendingEdits.ts`).
 */
export function createPasskey(params: {
  rpId: string;
  challenge: Uint8Array;
  origin: string;
}): CreatedPasskey {
  const privateKey = p256.utils.randomPrivateKey();
  const publicKey = p256.getPublicKey(privateKey, false); // uncompressed: 0x04 || x(32) || y(32)
  const x = publicKey.slice(1, 33);
  const y = publicKey.slice(33, 65);

  const credentialId = randomBytes(16);
  const userHandle = randomBytes(16);
  const coseP256PublicKey = encodeCoseP256PublicKey(x, y);

  const authData = buildAuthenticatorData({
    rpId: params.rpId,
    signCount: 0,
    attestedCredential: { credentialId, coseP256PublicKey },
  });
  const attestationObject = buildAttestationObject(authData);

  const clientDataJSON = JSON.stringify({
    type: 'webauthn.create',
    challenge: base64UrlEncode(params.challenge),
    origin: params.origin,
  });

  return {
    privateKeyHex: bytesToHex(privateKey),
    credentialIdB64: base64UrlEncode(credentialId),
    userHandleB64: base64UrlEncode(userHandle),
    clientDataJSON,
    attestationObject,
    signCount: 0,
    createdAt: Math.floor(Date.now() / 1000),
  };
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

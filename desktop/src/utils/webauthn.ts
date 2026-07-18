import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha2";
import { encodeBytes, encodeInt, encodeMap, encodeText } from "./cbor";

/**
 * Virtual WebAuthn authenticator — fundação do Passkey (item 3 do roadmap
 * pós-Fase 14). Gera credenciais P-256/ES256 e assina asserções, seguindo o
 * mesmo princípio do TOTP (ver totp.ts): lógica pura, sem UI, reimplementada
 * de forma independente em Dart (webauthn_service.dart), nunca no Rust.
 *
 * Escopo desta fase: só a cerimônia criptográfica em si. Não há interceptação
 * de `navigator.credentials` num site real — isso depende de um content
 * script na extensão que ainda não existe (ver PROJECT_STATE.md, roadmap).
 */

const AAGUID = new Uint8Array(16); // zeros — sem attestation de hardware real nesta fase.

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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
 * Encodes a P-256 public key as a COSE_Key CBOR map, per WebAuthn §6.5.1.1:
 * {1: 2 (kty: EC2), 3: -7 (alg: ES256), -1: 1 (crv: P-256), -2: x, -3: y}.
 * Key order matches this list exactly (not CBOR canonical sort) since that's
 * what relying-party libraries iterate/compare against in practice.
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
 * Builds the WebAuthn `authenticatorData` byte structure (§6.1):
 * rpIdHash(32) || flags(1) || signCount(4, BE) || [attestedCredentialData].
 * Flags: bit 0 (UP, user present) and bit 2 (UV, user verified) are always
 * set (0x05) since this virtual authenticator has no real presence/biometric
 * check; bit 6 (AT, attested credential data included) is added (0x40) only
 * during registration.
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
    [encodeText("fmt"), encodeText("none")],
    [encodeText("attStmt"), encodeMap([])],
    [encodeText("authData"), encodeBytes(authData)],
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
 * Runs a full (local, self-contained) WebAuthn registration ceremony: gera
 * um par de chaves P-256 novo, monta authenticatorData + attestationObject
 * "none". Não há relying party real nesta fase — o chamador fornece o
 * `challenge` (normalmente aleatório) e o `origin` só entra no clientDataJSON
 * por completude de formato.
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
    type: "webauthn.create",
    challenge: base64UrlEncode(params.challenge),
    origin: params.origin,
  });

  return {
    privateKeyHex: toHex(privateKey),
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
 * Runs a full (local, self-contained) WebAuthn authentication ceremony:
 * builds authenticatorData (no attested credential this time) + signs
 * `authenticatorData || SHA-256(clientDataJSON)` with ES256, per §6.3.3.
 */
export function signAssertion(params: {
  privateKeyHex: string;
  rpId: string;
  signCount: number;
  challenge: Uint8Array;
  origin: string;
}): SignedAssertion {
  const newSignCount = params.signCount + 1;
  const authenticatorData = buildAuthenticatorData({
    rpId: params.rpId,
    signCount: newSignCount,
  });

  const clientDataJSON = JSON.stringify({
    type: "webauthn.get",
    challenge: base64UrlEncode(params.challenge),
    origin: params.origin,
  });
  const clientDataHash = sha256(new TextEncoder().encode(clientDataJSON));
  const message = concatBytes(authenticatorData, clientDataHash);

  const privateKey = fromHex(params.privateKeyHex);
  // Explicit `lowS: true` for a canonical (malleability-resistant) signature
  // — needed even though this option's doc claims it's the default; it is
  // not, empirically, in the installed @noble/curves version. Dart's mirror
  // (PointyCastle's NormalizedECDSASigner) always produces low-S, so this
  // keeps both sides byte-identical for the same input.
  const signature = p256.sign(sha256(message), privateKey, { lowS: true });

  return {
    authenticatorData,
    clientDataJSON,
    signatureDer: signature.toDERRawBytes(),
    newSignCount,
  };
}

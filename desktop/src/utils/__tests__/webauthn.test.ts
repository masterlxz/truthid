import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha2";
import type {
  AuthenticationResponseJSON,
  RegistrationResponseJSON,
} from "@simplewebauthn/server";
import {
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import { describe, expect, it } from "vitest";
import {
  buildAuthenticatorData,
  createPasskey,
  encodeCoseP256PublicKey,
  signAssertion,
} from "../webauthn";
import { base64UrlEncode } from "../base64";

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

const RP_ID = "example.com";
const ORIGIN = "https://example.com";

describe("createPasskey + signAssertion (round-trip against an independent verifier)", () => {
  it("produces a registration that @simplewebauthn/server verifies as valid", async () => {
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const passkey = createPasskey({ rpId: RP_ID, challenge, origin: ORIGIN });

    const response: RegistrationResponseJSON = {
      id: passkey.credentialIdB64,
      rawId: passkey.credentialIdB64,
      response: {
        clientDataJSON: base64UrlEncode(
          new TextEncoder().encode(passkey.clientDataJSON),
        ),
        attestationObject: base64UrlEncode(passkey.attestationObject),
      },
      clientExtensionResults: {},
      type: "public-key",
    };

    const result = await verifyRegistrationResponse({
      response,
      expectedChallenge: base64UrlEncode(challenge),
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
    });

    expect(result.verified).toBe(true);
    if (!result.verified) throw new Error("unreachable");
    expect(result.registrationInfo.fmt).toBe("none");
    expect(result.registrationInfo.credential.counter).toBe(0);

    // Now sign an assertion with the same credential and verify it too, using
    // the exact WebAuthnCredential the registration step handed back — this
    // is the same object shape a real relying party would persist and reuse.
    const assertionChallenge = crypto.getRandomValues(new Uint8Array(32));
    const assertion = signAssertion({
      privateKeyHex: passkey.privateKeyHex,
      rpId: RP_ID,
      signCount: passkey.signCount,
      challenge: assertionChallenge,
      origin: ORIGIN,
    });

    const authResponse: AuthenticationResponseJSON = {
      id: passkey.credentialIdB64,
      rawId: passkey.credentialIdB64,
      response: {
        clientDataJSON: base64UrlEncode(
          new TextEncoder().encode(assertion.clientDataJSON),
        ),
        authenticatorData: base64UrlEncode(assertion.authenticatorData),
        signature: base64UrlEncode(assertion.signatureDer),
        userHandle: passkey.userHandleB64,
      },
      clientExtensionResults: {},
      type: "public-key",
    };

    const authResult = await verifyAuthenticationResponse({
      response: authResponse,
      expectedChallenge: base64UrlEncode(assertionChallenge),
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      credential: result.registrationInfo.credential,
    });

    expect(authResult.verified).toBe(true);
    expect(authResult.authenticationInfo.newCounter).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Fixed vector — cross-checked byte-for-byte against
// mobile/test/services/webauthn_service_test.dart. Any change to these
// constants or the expected hex output below must be mirrored there.
// ---------------------------------------------------------------------------
const FIXED_PRIVATE_KEY_HEX =
  "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
const FIXED_RP_ID = "vault.truthid.test";
const FIXED_CREDENTIAL_ID = new Uint8Array([
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
]);

const FIXED_CHALLENGE = new Uint8Array([
  9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
  9, 9, 9, 9, 9, 9,
]);
const FIXED_ORIGIN = "https://vault.truthid.test";

describe("fixed vector (cross-checked with the Dart implementation)", () => {
  it("derives the expected public key coordinates", () => {
    const publicKey = p256.getPublicKey(
      fromHex(FIXED_PRIVATE_KEY_HEX),
      false,
    );
    const x = publicKey.slice(1, 33);
    const y = publicKey.slice(33, 65);
    expect(toHex(x)).toBe(
      "515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f",
    );
    expect(toHex(y)).toBe(
      "4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354",
    );
  });

  it("builds the expected authenticatorData for a registration", () => {
    const publicKey = p256.getPublicKey(
      fromHex(FIXED_PRIVATE_KEY_HEX),
      false,
    );
    const x = publicKey.slice(1, 33);
    const y = publicKey.slice(33, 65);
    const cosePublicKey = encodeCoseP256PublicKey(x, y);
    const authData = buildAuthenticatorData({
      rpId: FIXED_RP_ID,
      signCount: 0,
      attestedCredential: {
        credentialId: FIXED_CREDENTIAL_ID,
        coseP256PublicKey: cosePublicKey,
      },
    });

    // rpIdHash(32) || flags(1)=0x45 || signCount(4)=0 || aaguid(16)=0 ||
    // credIdLen(2)=16 || credId(16) || COSE key.
    expect(toHex(sha256(new TextEncoder().encode(FIXED_RP_ID)))).toBe(
      toHex(authData.slice(0, 32)),
    );
    expect(authData[32]).toBe(0x45);
    expect(Array.from(authData.slice(33, 37))).toEqual([0, 0, 0, 0]);
    expect(toHex(authData.slice(37, 53))).toBe("00".repeat(16));
    expect(Array.from(authData.slice(53, 55))).toEqual([0, 16]);
    expect(toHex(authData.slice(55, 71))).toBe(toHex(FIXED_CREDENTIAL_ID));
    expect(toHex(authData.slice(71))).toBe(toHex(cosePublicKey));
  });

  it("signs the expected assertion (deterministic ECDSA, RFC 6979)", () => {
    const assertion = signAssertion({
      privateKeyHex: FIXED_PRIVATE_KEY_HEX,
      rpId: FIXED_RP_ID,
      signCount: 0,
      challenge: FIXED_CHALLENGE,
      origin: FIXED_ORIGIN,
    });

    expect(assertion.newSignCount).toBe(1);
    expect(assertion.clientDataJSON).toBe(
      JSON.stringify({
        type: "webauthn.get",
        challenge: base64UrlEncode(FIXED_CHALLENGE),
        origin: FIXED_ORIGIN,
      }),
    );
    expect(toHex(assertion.signatureDer)).toBe(
      "3045022100ccd3940608dc3a8c278322b9ec9facf9d9ad93d142f975ba7cf30c5ddaa50454022019f943e29741ee8cb0d4b142947d1cec20c403a50d2d3885c37461f0bce0763f",
    );
  });
});

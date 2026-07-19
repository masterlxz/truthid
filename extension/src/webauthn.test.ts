import { describe, expect, it } from 'vitest';
import { buildAuthenticatorData, signAssertion } from './webauthn';

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// ---------------------------------------------------------------------------
// Mesmo vetor fixo de `desktop/src/utils/__tests__/webauthn.test.ts`
// (cross-checado byte-a-byte com o Dart na Sessão 124-125) — prova que este
// port TS→TS pra extensão produz exatamente a mesma assinatura, sem precisar
// de nenhum site real (Sessão 132). Qualquer mudança nessas constantes ou no
// hex esperado abaixo tem que ser espelhada nos dois outros arquivos.
// ---------------------------------------------------------------------------
const FIXED_PRIVATE_KEY_HEX =
  '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const FIXED_RP_ID = 'vault.truthid.test';
const FIXED_CHALLENGE = new Uint8Array([
  9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
  9, 9, 9, 9, 9, 9,
]);
const FIXED_ORIGIN = 'https://vault.truthid.test';

describe('buildAuthenticatorData (sem attested credential — só login)', () => {
  it('produz rpIdHash(32) || flags(1)=0x05 || signCount(4, BE)', () => {
    const authData = buildAuthenticatorData({ rpId: FIXED_RP_ID, signCount: 1 });
    expect(authData.length).toBe(37);
    expect(authData[32]).toBe(0x05);
    expect(Array.from(authData.slice(33, 37))).toEqual([0, 0, 0, 1]);
  });
});

describe('signAssertion (vetor fixo, cross-checado com Desktop e Dart)', () => {
  it('assina a mesma asserção byte-a-byte (ECDSA determinístico, RFC 6979)', () => {
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
        type: 'webauthn.get',
        challenge: base64UrlEncode(FIXED_CHALLENGE),
        origin: FIXED_ORIGIN,
      }),
    );
    expect(toHex(assertion.signatureDer)).toBe(
      '3045022100ccd3940608dc3a8c278322b9ec9facf9d9ad93d142f975ba7cf30c5ddaa50454022019f943e29741ee8cb0d4b142947d1cec20c403a50d2d3885c37461f0bce0763f',
    );
  });

  it('incrementa o signCount a cada chamada, sem persistir sozinho', () => {
    const first = signAssertion({
      privateKeyHex: FIXED_PRIVATE_KEY_HEX,
      rpId: FIXED_RP_ID,
      signCount: 5,
      challenge: FIXED_CHALLENGE,
      origin: FIXED_ORIGIN,
    });
    expect(first.newSignCount).toBe(6);
  });
});

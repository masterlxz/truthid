import { describe, expect, it } from 'vitest';
import {
  AUTOFILL_ADDRESS_QR_TTL_MS,
  buildAutofillAddressQrPayload,
  buildQrPayload,
  buildVaultEditQrPayload,
  randomSessionId,
  SESSION_TTL_MS,
  toQrPayload,
  VAULT_EDIT_QR_TTL_MS,
} from './qrPayload';

describe('randomSessionId', () => {
  it('gera 32 caracteres hex (16 bytes)', () => {
    const id = randomSessionId();
    expect(id).toHaveLength(32);
    expect(id).toMatch(/^[0-9a-f]{32}$/);
  });

  it('nunca repete entre chamadas', () => {
    const ids = new Set(Array.from({ length: 20 }, () => randomSessionId()));
    expect(ids.size).toBe(20);
  });
});

describe('buildQrPayload (vault-session)', () => {
  it('monta o payload v1 com o TTL certo', () => {
    const now = 1_000_000;
    const payload = buildQrPayload('abc', '0xdeadbeef', now);

    expect(payload).toEqual({
      action: 'truthid-vault-session',
      v: 1,
      sessionId: 'abc',
      ephemeralPubKey: '0xdeadbeef',
      expiresAt: now + SESSION_TTL_MS,
    });
  });
});

describe('toQrPayload', () => {
  it('reconstrói o payload reusando um expiresAt já existente', () => {
    const payload = toQrPayload('abc', '0xdeadbeef', 12345);
    expect(payload.expiresAt).toBe(12345);
  });
});

describe('buildVaultEditQrPayload', () => {
  it('monta o payload v1 com appName fixo e o TTL certo', () => {
    const now = 2_000_000;
    const payload = buildVaultEditQrPayload('abc', '0xdeadbeef', now);

    expect(payload).toEqual({
      action: 'truthid-vault-edit',
      v: 1,
      sessionId: 'abc',
      ephemeralPubKey: '0xdeadbeef',
      expiresAt: now + VAULT_EDIT_QR_TTL_MS,
      appName: 'TruthID Extension',
    });
  });
});

describe('buildAutofillAddressQrPayload (Fase 15.4, fatia 1)', () => {
  it('monta o payload v1 com appName fixo e o TTL certo', () => {
    const now = 3_000_000;
    const payload = buildAutofillAddressQrPayload('abc', '0xdeadbeef', now);

    expect(payload).toEqual({
      action: 'truthid-autofill-address',
      v: 1,
      sessionId: 'abc',
      ephemeralPubKey: '0xdeadbeef',
      expiresAt: now + AUTOFILL_ADDRESS_QR_TTL_MS,
      appName: 'TruthID Extension',
    });
  });

  it('usa Date.now() quando `now` não é passado', () => {
    const before = Date.now();
    const payload = buildAutofillAddressQrPayload('abc', '0xdeadbeef');
    const after = Date.now();

    expect(payload.expiresAt).toBeGreaterThanOrEqual(before + AUTOFILL_ADDRESS_QR_TTL_MS);
    expect(payload.expiresAt).toBeLessThanOrEqual(after + AUTOFILL_ADDRESS_QR_TTL_MS);
  });
});

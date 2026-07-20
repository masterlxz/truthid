import { describe, expect, it, vi } from 'vitest';
import { startMobileDelivery } from './mobileDelivery';

const proposal = {
  site: 'example.com',
  url: 'https://example.com',
  username: '',
  password: '',
  notes: '',
  passkey: {
    rp_id: 'example.com',
    credential_id_b64: 'AAAA',
    user_handle_b64: 'BBBB',
    private_key_hex: '00'.repeat(32),
    sign_count: 0,
    created_at: 0,
  },
};

describe('startMobileDelivery', () => {
  it('monta um payload de QR válido com action/v/schema esperados', () => {
    const session = startMobileDelivery(proposal);
    expect(session.qrPayload.action).toBe('truthid-vault-edit');
    expect(session.qrPayload.v).toBe(1);
    expect(session.qrPayload.sessionId).toHaveLength(32);
    expect(session.qrPayload.ephemeralPubKey).toMatch(/^[0-9a-f]{66}$/);
    expect(session.qrPayload.expiresAt).toBeGreaterThan(Date.now());
  });

  it('send() cifra a proposta e chama push com o mesmo sessionId do QR', async () => {
    const push = vi.fn(async (_sessionId: string, _body: Uint8Array) => true);
    const session = startMobileDelivery(proposal, { push });

    const ok = await session.send();

    expect(ok).toBe(true);
    expect(push).toHaveBeenCalledTimes(1);
    const [sentSessionId, encryptedBody] = push.mock.calls[0];
    expect(sentSessionId).toBe(session.qrPayload.sessionId);
    expect(encryptedBody).toBeInstanceOf(Uint8Array);
    expect(encryptedBody.length).toBeGreaterThan(12 + 16);
  });

  it('sendTo() cifra a proposta e tenta cada porta candidata no host até uma aceitar', async () => {
    const putAt = vi
      .fn(async (_host: string, port: number, _sessionId: string, _body: Uint8Array) => port === 48052)
      .mockName('putAt');
    const session = startMobileDelivery(proposal, { putAt });

    const ok = await session.sendTo('192.168.1.42');

    expect(ok).toBe(true);
    expect(putAt).toHaveBeenCalledTimes(3);
    for (const call of putAt.mock.calls) {
      expect(call[0]).toBe('192.168.1.42');
      expect(call[2]).toBe(session.qrPayload.sessionId);
    }
  });

  it('sendTo() devolve false se nenhuma porta aceitar', async () => {
    const putAt = vi.fn(async () => false);
    const session = startMobileDelivery(proposal, { putAt });

    expect(await session.sendTo('192.168.1.42')).toBe(false);
  });

  it('duas sessões geram sessionIds diferentes', () => {
    const a = startMobileDelivery(proposal);
    const b = startMobileDelivery(proposal);
    expect(a.qrPayload.sessionId).not.toBe(b.qrPayload.sessionId);
  });
});

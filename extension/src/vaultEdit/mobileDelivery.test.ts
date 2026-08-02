import { describe, expect, it, vi } from 'vitest';
import { startMobileDelivery } from './mobileDelivery';

const proposals = [
  {
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
  },
];

describe('startMobileDelivery', () => {
  it('monta um payload de QR válido com action/v/schema esperados', () => {
    const session = startMobileDelivery(proposals);
    expect(session.qrPayload.action).toBe('truthid-vault-edit');
    expect(session.qrPayload.v).toBe(1);
    expect(session.qrPayload.sessionId).toHaveLength(32);
    expect(session.qrPayload.ephemeralPubKey).toMatch(/^[0-9a-f]{66}$/);
    expect(session.qrPayload.expiresAt).toBeGreaterThan(Date.now());
  });

  it('send() cifra a proposta e chama push com o mesmo sessionId do QR', async () => {
    const push = vi.fn(async (_sessionId: string, _body: Uint8Array) => true);
    const session = startMobileDelivery(proposals, { push });

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
    const session = startMobileDelivery(proposals, { putAt });

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
    const session = startMobileDelivery(proposals, { putAt });

    expect(await session.sendTo('192.168.1.42')).toBe(false);
  });

  it('duas sessões geram sessionIds diferentes', () => {
    const a = startMobileDelivery(proposals);
    const b = startMobileDelivery(proposals);
    expect(a.qrPayload.sessionId).not.toBe(b.qrPayload.sessionId);
  });

  it('dispara o publish do dead-drop via mensagem pro background, não chamando IPFS direto', async () => {
    const sendMessage = vi.fn(async (_message: { type: string; sessionId: string; bodyBase64: string }) => undefined);
    startMobileDelivery(proposals, { sendMessage: sendMessage as unknown as typeof chrome.runtime.sendMessage });

    // A chamada acontece dentro de uma promise encadeada no corpo da função
    // (fire-and-forget, `encryptedBody()` usa `crypto.subtle` por baixo) —
    // `vi.waitFor` poll até resolver em vez de contar ticks de microtask a
    // mão, que é frágil pra promises encadeadas via APIs assíncronas nativas.
    await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));

    const [message] = sendMessage.mock.calls[0];
    expect(message).toMatchObject({ type: 'truthid-vault-edit-start-dead-drop-publish' });
    expect(typeof message.sessionId).toBe('string');
    expect(typeof message.bodyBase64).toBe('string');
  });

  it('sem deps.sendMessage nem chrome global, não lança (ambiente de teste sem extensão)', async () => {
    const session = startMobileDelivery(proposals);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(session.qrPayload.sessionId).toHaveLength(32);
  });

  it('sync em lote (P29): send() cifra a lista inteira, não só o 1º item', async () => {
    const batch = [
      { site: 'one.com', url: '', username: 'alice', password: 'hunter2', notes: '' },
      { site: 'two.com', url: '', username: 'bob', password: 'hunter3', notes: '' },
    ];
    let pushedBody: Uint8Array | undefined;
    const push = vi.fn(async (_sessionId: string, body: Uint8Array) => {
      pushedBody = body;
      return true;
    });
    const session = startMobileDelivery(batch, { push });

    await session.send();

    const { deriveVaultEditContentKey, decryptVaultEditContent } = await import('./cipher');
    const key = deriveVaultEditContentKey(session.qrPayload.sessionId);
    const decrypted = await decryptVaultEditContent(pushedBody!, key);
    const decoded = JSON.parse(new TextDecoder().decode(decrypted));
    expect(decoded).toEqual(batch);
  });
});

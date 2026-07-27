import { afterEach, describe, expect, it, vi } from 'vitest';
import { pullFromDeadDrop } from './deadDropPull';
import {
  AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE,
  AUTOFILL_START_DEAD_DROP_POLL_MESSAGE,
} from './messages';

type Listener = (message: { type?: string; sessionId?: string; blob?: string }) => void;

function buildFakeChrome() {
  const listeners: Listener[] = [];
  const sendMessage = vi.fn(async () => undefined);
  return {
    fakeChrome: {
      runtime: {
        sendMessage,
        onMessage: {
          addListener: vi.fn((l: Listener) => listeners.push(l)),
          removeListener: vi.fn((l: Listener) => {
            const i = listeners.indexOf(l);
            if (i !== -1) listeners.splice(i, 1);
          }),
        },
      },
    },
    sendMessage,
    emit: (message: { type?: string; sessionId?: string; blob?: string }) => {
      for (const l of [...listeners]) l(message);
    },
    listenerCount: () => listeners.length,
  };
}

describe('pullFromDeadDrop', () => {
  afterEach(() => {
    // @ts-expect-error -- só existe em teste
    delete globalThis.chrome;
    vi.useRealTimers();
  });

  it('pede pro background começar o polling com sessionId e expiresAt', () => {
    const { fakeChrome, sendMessage } = buildFakeChrome();
    globalThis.chrome = fakeChrome as unknown as typeof chrome;

    void pullFromDeadDrop('session-abc', Date.now() + 60_000);

    expect(sendMessage).toHaveBeenCalledWith({
      type: AUTOFILL_START_DEAD_DROP_POLL_MESSAGE,
      sessionId: 'session-abc',
      expiresAt: expect.any(Number),
    });
  });

  it('resolve com o blob quando chega AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE pro sessionId certo', async () => {
    const { fakeChrome, emit } = buildFakeChrome();
    globalThis.chrome = fakeChrome as unknown as typeof chrome;

    const promise = pullFromDeadDrop('session-abc', Date.now() + 60_000);
    emit({
      type: AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE,
      sessionId: 'session-abc',
      blob: 'ZmFrZS1ibG9i',
    });

    await expect(promise).resolves.toBe('ZmFrZS1ibG9i');
  });

  it('ignora mensagem de outro sessionId', async () => {
    vi.useFakeTimers();
    const { fakeChrome, emit } = buildFakeChrome();
    globalThis.chrome = fakeChrome as unknown as typeof chrome;

    const promise = pullFromDeadDrop('session-abc', Date.now() + 1000);
    emit({
      type: AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE,
      sessionId: 'session-other',
      blob: 'ZmFrZS1ibG9i',
    });

    vi.advanceTimersByTime(1000);
    await expect(promise).resolves.toBeNull();
  });

  it('resolve null quando expira sem resposta', async () => {
    vi.useFakeTimers();
    const { fakeChrome } = buildFakeChrome();
    globalThis.chrome = fakeChrome as unknown as typeof chrome;

    const promise = pullFromDeadDrop('session-abc', Date.now() + 1000);
    vi.advanceTimersByTime(1000);

    await expect(promise).resolves.toBeNull();
  });

  it('remove o listener depois de resolver, não reage a mensagens tardias', async () => {
    const { fakeChrome, emit, listenerCount } = buildFakeChrome();
    globalThis.chrome = fakeChrome as unknown as typeof chrome;

    const promise = pullFromDeadDrop('session-abc', Date.now() + 60_000);
    emit({
      type: AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE,
      sessionId: 'session-abc',
      blob: 'ZmFrZS1ibG9i',
    });
    await promise;

    expect(listenerCount()).toBe(0);
  });
});

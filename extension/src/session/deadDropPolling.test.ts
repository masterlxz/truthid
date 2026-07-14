import { describe, expect, it, vi } from 'vitest';

import { tryFetchDeadDrop } from './deadDropPolling';
import { computeIpnsName } from './ipnsKey';

function fakeResponse(ok: boolean, body: Uint8Array = new Uint8Array()): Response {
  return {
    ok,
    arrayBuffer: async () => body.buffer as ArrayBuffer,
  } as Response;
}

describe('tryFetchDeadDrop', () => {
  const sessionId = '000102030405060708090a0b0c0d0e0f';

  it('devolve os bytes crus quando o gateway responde 200', async () => {
    const body = new Uint8Array([1, 2, 3, 4]);
    const fetchGateway = vi.fn(async () => fakeResponse(true, body));

    const result = await tryFetchDeadDrop(sessionId, { fetchGateway });

    expect(result).toEqual(body);
  });

  it('devolve null quando o gateway responde não-200 (ex: 500 de nome não propagado)', async () => {
    const fetchGateway = vi.fn(async () => fakeResponse(false));

    const result = await tryFetchDeadDrop(sessionId, { fetchGateway });

    expect(result).toBeNull();
  });

  it('devolve null (não lança) em erro de rede', async () => {
    const fetchGateway = vi.fn(async () => {
      throw new Error('network down');
    });

    const result = await tryFetchDeadDrop(sessionId, { fetchGateway });

    expect(result).toBeNull();
  });

  it('busca a URL /ipns/<nome> derivado do sessionId, com cache-busting e no-store', async () => {
    const fetchGateway = vi.fn(
      async (_input: string | URL | Request, _init?: RequestInit) => fakeResponse(true),
    );
    const expectedName = computeIpnsName(sessionId);

    await tryFetchDeadDrop(sessionId, {
      fetchGateway,
      gatewayUrl: 'https://gateway.example',
    });

    expect(fetchGateway).toHaveBeenCalledTimes(1);
    const [url, init] = fetchGateway.mock.calls[0];
    expect(url).toMatch(
      new RegExp(`^https://gateway\\.example/ipns/${expectedName}\\?cachebust=\\d+$`),
    );
    expect((init as RequestInit).cache).toBe('no-store');
  });
});

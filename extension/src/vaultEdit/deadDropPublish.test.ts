import { afterEach, describe, expect, it, vi } from 'vitest';

import { deriveDeadDropKey } from './deadDropIpnsKey';
import { publishDeadDrop } from './deadDropPublish';

const sessionIdHex = '000102030405060708090a0b0c0d0e0f';
const content = new Uint8Array([1, 2, 3, 4]);

function stubChromeStorage(kuboEndpointUrl: string | undefined): void {
  vi.stubGlobal('chrome', {
    storage: {
      local: {
        get: vi.fn(async () => (kuboEndpointUrl ? { truthid_vault_edit_pinning_provider: { kuboEndpointUrl } } : {})),
      },
    },
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('publishDeadDrop', () => {
  it('devolve null sem chamar fetch quando não há provider configurado', async () => {
    stubChromeStorage(undefined);
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const result = await publishDeadDrop(sessionIdHex, content);

    expect(result).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('publica com sucesso: add -> key/import -> name/publish -> key/rm, devolve o ipnsName derivado', async () => {
    stubChromeStorage('http://192.168.1.53:5001');
    const calls: string[] = [];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      calls.push(url);
      if (url.includes('/api/v0/add')) {
        return new Response('{"Hash":"QmTest123"}\n', { status: 200 });
      }
      if (url.includes('/api/v0/key/import')) {
        return new Response('{}', { status: 200 });
      }
      if (url.includes('/api/v0/name/publish')) {
        return new Response('{"Name":"k51..."}', { status: 200 });
      }
      if (url.includes('/api/v0/key/rm')) {
        return new Response('{}', { status: 200 });
      }
      throw new Error(`unexpected url: ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const expected = deriveDeadDropKey(sessionIdHex);
    const result = await publishDeadDrop(sessionIdHex, content);

    expect(result).toBe(expected.ipnsName);
    expect(calls).toHaveLength(4);
    expect(calls[0]).toContain('/api/v0/add');
    expect(calls[1]).toContain('/api/v0/key/import');
    expect(calls[1]).toContain('format=libp2p-protobuf-cleartext');
    expect(calls[2]).toContain('/api/v0/name/publish');
    expect(calls[2]).toContain('arg=%2Fipfs%2FQmTest123');
    expect(calls[3]).toContain('/api/v0/key/rm');
  });

  it('trata "already exists" no key/import como sucesso, continua pro publish', async () => {
    stubChromeStorage('http://192.168.1.53:5001');
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/v0/add')) return new Response('{"Hash":"QmTest123"}', { status: 200 });
      if (url.includes('/api/v0/key/import')) return new Response('key already exists', { status: 500 });
      if (url.includes('/api/v0/name/publish')) return new Response('{"Name":"k51..."}', { status: 200 });
      if (url.includes('/api/v0/key/rm')) return new Response('{}', { status: 200 });
      throw new Error(`unexpected url: ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await publishDeadDrop(sessionIdHex, content);
    expect(result).not.toBeNull();
  });

  it('devolve null (best-effort) se o kubo add falhar', async () => {
    stubChromeStorage('http://192.168.1.53:5001');
    vi.stubGlobal('fetch', vi.fn(async () => new Response('boom', { status: 500 })));

    const result = await publishDeadDrop(sessionIdHex, content);
    expect(result).toBeNull();
  });

  it('devolve null (best-effort) se o name/publish falhar, mesmo com add/import ok', async () => {
    stubChromeStorage('http://192.168.1.53:5001');
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/v0/add')) return new Response('{"Hash":"QmTest123"}', { status: 200 });
      if (url.includes('/api/v0/key/import')) return new Response('{}', { status: 200 });
      if (url.includes('/api/v0/name/publish')) return new Response('boom', { status: 500 });
      if (url.includes('/api/v0/key/rm')) return new Response('{}', { status: 200 });
      throw new Error(`unexpected url: ${url}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await publishDeadDrop(sessionIdHex, content);
    expect(result).toBeNull();
  });
});

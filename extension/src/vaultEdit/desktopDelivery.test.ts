import { afterEach, describe, expect, it, vi } from 'vitest';
import { findDesktopPort, sendToDesktop } from './desktopDelivery';

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

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('findDesktopPort', () => {
  it('retorna a primeira porta que responde ping com service truthid-desktop', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      if (url === 'http://127.0.0.1:47952/truthid/v1/ping') {
        return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
      }
      throw new Error('connection refused');
    });
    vi.stubGlobal('fetch', fetchMock);

    const port = await findDesktopPort([47950, 47951, 47952, 47953]);
    expect(port).toBe(47952);
  });

  it('retorna null quando nenhuma porta responde', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('connection refused'); }));
    const port = await findDesktopPort([47950, 47951]);
    expect(port).toBeNull();
  });

  it('ignora uma porta que responde mas não é o TruthID', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ service: 'something-else' }), { status: 200 })),
    );
    const port = await findDesktopPort([47950]);
    expect(port).toBeNull();
  });
});

describe('sendToDesktop', () => {
  it('not-found quando nenhuma porta responde ping', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('connection refused'); }));
    const result = await sendToDesktop(proposals, [47950]);
    expect(result.status).toBe('not-found');
  });

  it('encaminha o status/id devolvido pelo Desktop numa aprovação', async () => {
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (url.endsWith('/truthid/v1/ping')) {
        return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
      }
      if (url.endsWith('/truthid/v1/vault-edit')) {
        expect(JSON.parse(init!.body as string)).toEqual(proposals);
        return new Response(JSON.stringify({ status: 'approved', id: 'abc123' }), { status: 200 });
      }
      throw new Error('unexpected url ' + url);
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendToDesktop(proposals, [47950]);
    expect(result).toEqual({ status: 'approved', id: 'abc123' });
  });

  it('encaminha rejected', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url.endsWith('/truthid/v1/ping')) {
          return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
        }
        return new Response(JSON.stringify({ status: 'rejected' }), { status: 403 });
      }),
    );
    const result = await sendToDesktop(proposals, [47950]);
    expect(result.status).toBe('rejected');
  });

  it('erro de rede no POST retorna status error', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url.endsWith('/truthid/v1/ping')) {
          return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
        }
        throw new Error('connection reset');
      }),
    );
    const result = await sendToDesktop(proposals, [47950]);
    expect(result.status).toBe('error');
  });

  it('sync em lote (P29): manda a lista inteira num único POST', async () => {
    const batch = [
      { site: 'one.com', url: '', username: 'alice', password: 'hunter2', notes: '' },
      { site: 'two.com', url: '', username: 'bob', password: 'hunter3', notes: '' },
    ];
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (url.endsWith('/truthid/v1/ping')) {
        return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
      }
      expect(JSON.parse(init!.body as string)).toEqual(batch);
      return new Response(JSON.stringify({ status: 'approved', id: 'abc123' }), { status: 200 });
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendToDesktop(batch, [47950]);
    expect(result).toEqual({ status: 'approved', id: 'abc123' });
  });
});

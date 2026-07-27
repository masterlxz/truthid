import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchAddressFromDesktop, fetchCreditCardFromDesktop } from './desktopDelivery';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('fetchAddressFromDesktop', () => {
  it('not-found quando nenhuma porta responde ping', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('connection refused');
      }),
    );
    const result = await fetchAddressFromDesktop([47950]);
    expect(result).toEqual({ status: 'not-found' });
  });

  it('encaminha o endereço devolvido pelo Desktop numa aprovação', async () => {
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (url.endsWith('/truthid/v1/ping')) {
        return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
      }
      if (url.endsWith('/truthid/v1/autofill-address')) {
        expect(init?.method).toBe('POST');
        return new Response(
          JSON.stringify({ status: 'filled', address: { label: 'Home', street: 'Main St' } }),
          { status: 200 },
        );
      }
      throw new Error('unexpected url ' + url);
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await fetchAddressFromDesktop([47950]);
    expect(result).toEqual({
      status: 'filled',
      address: { label: 'Home', street: 'Main St' },
    });
  });

  it('encaminha no-addresses', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url.endsWith('/truthid/v1/ping')) {
          return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
        }
        return new Response(JSON.stringify({ status: 'no-addresses' }), { status: 200 });
      }),
    );
    const result = await fetchAddressFromDesktop([47950]);
    expect(result.status).toBe('no-addresses');
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
    const result = await fetchAddressFromDesktop([47950]);
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
    const result = await fetchAddressFromDesktop([47950]);
    expect(result.status).toBe('error');
  });
});

describe('fetchCreditCardFromDesktop', () => {
  it('not-found quando nenhuma porta responde ping', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('connection refused');
      }),
    );
    const result = await fetchCreditCardFromDesktop([47950]);
    expect(result).toEqual({ status: 'not-found' });
  });

  it('encaminha o cartão devolvido pelo Desktop numa aprovação', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      if (url.endsWith('/truthid/v1/ping')) {
        return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
      }
      if (url.endsWith('/truthid/v1/autofill-creditcard')) {
        return new Response(
          JSON.stringify({ status: 'filled', card: { label: 'Nubank', card_number: '4111' } }),
          { status: 200 },
        );
      }
      throw new Error('unexpected url ' + url);
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await fetchCreditCardFromDesktop([47950]);
    expect(result).toEqual({
      status: 'filled',
      card: { label: 'Nubank', card_number: '4111' },
    });
  });

  it('encaminha no-cards', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url.endsWith('/truthid/v1/ping')) {
          return new Response(JSON.stringify({ service: 'truthid-desktop' }), { status: 200 });
        }
        return new Response(JSON.stringify({ status: 'no-cards' }), { status: 200 });
      }),
    );
    const result = await fetchCreditCardFromDesktop([47950]);
    expect(result.status).toBe('no-cards');
  });
});

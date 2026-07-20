import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { loadPinningProviderConfig, savePinningProviderConfig } from './pinningProviderConfig';

function inMemoryChromeStorage(): void {
  const store: Record<string, unknown> = {};
  (globalThis as unknown as { chrome: unknown }).chrome = {
    storage: {
      local: {
        get: async (key: string) => ({ [key]: store[key] }),
        set: async (items: Record<string, unknown>) => {
          Object.assign(store, items);
        },
        remove: async (key: string) => {
          delete store[key];
        },
      },
    },
  };
}

beforeEach(() => {
  inMemoryChromeStorage();
});

afterEach(() => {
  delete (globalThis as unknown as { chrome?: unknown }).chrome;
});

describe('pinningProviderConfig', () => {
  it('devolve null quando nada foi salvo', async () => {
    expect(await loadPinningProviderConfig()).toBeNull();
  });

  it('salva e recupera o endpoint', async () => {
    await savePinningProviderConfig('http://192.168.1.53:5001');
    expect(await loadPinningProviderConfig()).toEqual({
      kuboEndpointUrl: 'http://192.168.1.53:5001',
    });
  });

  it('trima espaços', async () => {
    await savePinningProviderConfig('  http://192.168.1.53:5001  ');
    expect(await loadPinningProviderConfig()).toEqual({
      kuboEndpointUrl: 'http://192.168.1.53:5001',
    });
  });

  it('salvar string vazia remove a config', async () => {
    await savePinningProviderConfig('http://192.168.1.53:5001');
    await savePinningProviderConfig('  ');
    expect(await loadPinningProviderConfig()).toBeNull();
  });
});

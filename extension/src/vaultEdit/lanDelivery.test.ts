import { describe, expect, it, vi } from 'vitest';
import { pushToMobile } from './lanDelivery';

describe('pushToMobile', () => {
  it('false quando não há IPs locais', async () => {
    const ok = await pushToMobile('abc123', new Uint8Array([1, 2, 3]), {
      getLocalIps: async () => [],
    });
    expect(ok).toBe(false);
  });

  it('true assim que algum host aceita o PUT', async () => {
    const putAt = vi.fn(async (host: string) => host === '192.168.1.42');
    const ok = await pushToMobile('abc123', new Uint8Array([1, 2, 3]), {
      getLocalIps: async () => ['192.168.1.1'],
      putAt,
      concurrency: 10,
    });
    expect(ok).toBe(true);
    expect(putAt).toHaveBeenCalled();
  });

  it('false quando nenhum host aceita', async () => {
    const ok = await pushToMobile('abc123', new Uint8Array([1, 2, 3]), {
      getLocalIps: async () => ['10.0.0.1'],
      putAt: async () => false,
      concurrency: 300,
    });
    expect(ok).toBe(false);
  });
});

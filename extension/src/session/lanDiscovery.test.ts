import { describe, expect, it, vi } from 'vitest';
import { CANDIDATE_PORTS, subnetHosts, sweepLan } from './lanDiscovery';

describe('subnetHosts', () => {
  it('enumerates all 254 hosts of the /24', () => {
    const hosts = subnetHosts('192.168.1.42');
    expect(hosts).toHaveLength(254);
    expect(hosts[0]).toBe('192.168.1.1');
    expect(hosts[253]).toBe('192.168.1.254');
  });

  it('returns empty for a malformed IP', () => {
    expect(subnetHosts('not-an-ip')).toEqual([]);
  });
});

describe('sweepLan', () => {
  it('returns null immediately when no local IPs are known (e.g. Firefox)', async () => {
    const fetchAt = vi.fn();
    const result = await sweepLan('session-abc', {
      getLocalIps: async () => [],
      fetchAt,
    });

    expect(result).toBeNull();
    expect(fetchAt).not.toHaveBeenCalled();
  });

  it('sweeps the fixed port list against every host and returns the first hit', async () => {
    const fetchAt = vi.fn(async (host: string, port: number) => {
      if (host === '192.168.1.7' && port === CANDIDATE_PORTS[2]) {
        return 'found-blob';
      }
      return null;
    });

    const result = await sweepLan('session-abc', {
      getLocalIps: async () => ['192.168.1.99'],
      fetchAt,
      concurrency: 50,
    });

    expect(result).toBe('found-blob');
    // Confirma que varreu com a lista fixa de portas, não uma porta aleatória.
    const attemptedPorts = new Set(fetchAt.mock.calls.map((call) => call[1]));
    expect([...attemptedPorts].sort((a, b) => a - b)).toEqual(CANDIDATE_PORTS);
  });

  it('exits early on the first hit without waiting for the full sweep', async () => {
    let callCount = 0;
    const fetchAt = vi.fn(async (host: string) => {
      callCount++;
      return host === '192.168.1.1' ? 'first-batch-hit' : null;
    });

    const result = await sweepLan('session-abc', {
      getLocalIps: async () => ['192.168.1.1'],
      fetchAt,
      concurrency: 5, // small batch so we can prove it stops after batch 1
    });

    expect(result).toBe('first-batch-hit');
    // 1 host (192.168.1.1) x 5 candidate ports = 5 calls in the first batch;
    // it should not have swept the remaining 253 hosts.
    expect(callCount).toBe(CANDIDATE_PORTS.length);
  });

  it('returns null when nobody on the subnet responds', async () => {
    const fetchAt = vi.fn(async () => null);

    const result = await sweepLan('session-abc', {
      getLocalIps: async () => ['10.0.0.5'],
      fetchAt,
      concurrency: 100,
    });

    expect(result).toBeNull();
  });
});

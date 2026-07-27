import { describe, expect, it, vi } from 'vitest';
import { fetchMobileBlobAt, sweepMobileForBlob } from './lanPull';
import { MOBILE_CANDIDATE_PORTS } from '../vaultEdit/lanDelivery';

describe('sweepMobileForBlob', () => {
  it('null quando não há IPs locais', async () => {
    const blob = await sweepMobileForBlob('abc123', {
      getLocalIps: async () => [],
    });
    expect(blob).toBeNull();
  });

  it('devolve o primeiro blob encontrado', async () => {
    const fetchAt = vi.fn(async (host: string) =>
      host === '192.168.1.42' ? 'ZmFrZS1ibG9i' : null,
    );
    const blob = await sweepMobileForBlob('abc123', {
      getLocalIps: async () => ['192.168.1.1'],
      fetchAt,
      concurrency: 10,
    });
    expect(blob).toBe('ZmFrZS1ibG9i');
    expect(fetchAt).toHaveBeenCalled();
  });

  it('null quando ninguém responde', async () => {
    const blob = await sweepMobileForBlob('abc123', {
      getLocalIps: async () => ['10.0.0.1'],
      fetchAt: async () => null,
      concurrency: 300,
    });
    expect(blob).toBeNull();
  });

  it('varre exatamente MOBILE_CANDIDATE_PORTS por host, não o bloco vault-only', async () => {
    const seenPorts: number[] = [];
    const fetchAt = vi.fn(async (_host: string, port: number) => {
      seenPorts.push(port);
      return null;
    });
    await sweepMobileForBlob('abc123', {
      getLocalIps: async () => ['10.0.0.1'],
      fetchAt,
    });
    // 254 hosts do /24 x MOBILE_CANDIDATE_PORTS, mas basta confirmar que só
    // as portas certas foram usadas (nunca as de leitura do vault).
    for (const port of new Set(seenPorts)) {
      expect(MOBILE_CANDIDATE_PORTS).toContain(port);
    }
  });
});

describe('fetchMobileBlobAt', () => {
  it('tenta cada porta candidata até achar uma resposta', async () => {
    const attemptedPorts: number[] = [];
    const fetchAt = vi.fn(async (_host: string, port: number) => {
      attemptedPorts.push(port);
      return port === MOBILE_CANDIDATE_PORTS[2] ? 'ZmFrZS1ibG9i' : null;
    });

    const blob = await fetchMobileBlobAt('192.168.1.42', 'abc123', fetchAt);

    expect(blob).toBe('ZmFrZS1ibG9i');
    expect(attemptedPorts).toEqual(MOBILE_CANDIDATE_PORTS.slice(0, 3));
  });

  it('null quando nenhuma porta responde', async () => {
    const blob = await fetchMobileBlobAt('192.168.1.42', 'abc123', async () => null);
    expect(blob).toBeNull();
  });
});

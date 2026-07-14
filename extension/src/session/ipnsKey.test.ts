import { describe, expect, it } from 'vitest';

import { computeIpnsName } from './ipnsKey';

describe('computeIpnsName', () => {
  // Mesmo par usado em `mobile/test/services/ipns_key_service_test.dart` —
  // validado contra um Kubo 0.42.0 real (não só round-trip interno, mesmo
  // padrão que pegou o bug do ECIES nas Sessões 92 e 99): importou-se a
  // chave derivada de `sessionIdHex` de verdade via
  // `POST /api/v0/key/import?format=libp2p-protobuf-cleartext`, e o `Id`
  // que o Kubo devolveu bateu byte-a-byte com este valor. Fecha o loop de
  // interoperabilidade Mobile ↔ Kubo ↔ Extensão de forma determinística e
  // offline.
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';
  const expectedIpnsName =
    'k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh';

  it('bate com o fixture validado contra Kubo real', () => {
    expect(computeIpnsName(sessionIdHex)).toBe(expectedIpnsName);
  });

  it('é determinístico', () => {
    expect(computeIpnsName(sessionIdHex)).toBe(computeIpnsName(sessionIdHex));
  });

  it('sessionIds diferentes derivam nomes diferentes', () => {
    expect(computeIpnsName(sessionIdHex)).not.toBe(
      computeIpnsName('0f0e0d0c0b0a09080706050403020100'),
    );
  });

  it('sempre começa com o prefixo multibase base36 "k"', () => {
    expect(computeIpnsName(sessionIdHex).startsWith('k')).toBe(true);
  });
});

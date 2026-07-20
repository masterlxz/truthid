import { describe, expect, it } from 'vitest';

import { deriveDeadDropKey } from './deadDropIpnsKey';

describe('deriveDeadDropKey', () => {
  // Mesmo `sessionIdHex` de fixture usado em `session/ipnsKey.test.ts`, mas
  // com salt/info domain-separados — o valor abaixo foi calculado rodando
  // este mesmo código (não round-trip cego: a codificação
  // protobuf/multihash/CID/base36 já foi validada contra um Kubo 0.42.0 real
  // pelo fixture de `session/ipnsKey.ts`/`ipns_key_service.dart`, aqui só
  // muda o material de entrada do HKDF). Precisa bater byte-a-byte com
  // `mobile/test/services/vault_edit_dead_drop_ipns_key_service_test.dart`.
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';
  const expectedIpnsName = 'k51qzi5uqu5djgtmynxex3q39osopskdt54vg2txhdkfjcwo1114qqv9n9uld9';
  const expectedPrivateKeyProtobufHex =
    '08011240013d3d93709cf05c51ae0854cca8195e81585a474f91d4b19d644464fabfbb4883c5a3bfbd2b79f05f99e265b690145687f74d6f76aeffdd3aacd4ba52447cad';

  it('bate com o fixture calculado', () => {
    const key = deriveDeadDropKey(sessionIdHex);
    expect(key.ipnsName).toBe(expectedIpnsName);
    expect(Buffer.from(key.privateKeyProtobuf).toString('hex')).toBe(
      expectedPrivateKeyProtobufHex,
    );
  });

  it('é determinístico', () => {
    expect(deriveDeadDropKey(sessionIdHex)).toEqual(deriveDeadDropKey(sessionIdHex));
  });

  it('sessionIds diferentes derivam pares diferentes', () => {
    const a = deriveDeadDropKey(sessionIdHex);
    const b = deriveDeadDropKey('0f0e0d0c0b0a09080706050403020100');
    expect(a.ipnsName).not.toBe(b.ipnsName);
  });

  it('deriva um nome diferente do namespace de leitura (domain separation)', async () => {
    const { computeIpnsName } = await import('../session/ipnsKey');
    const deadDrop = deriveDeadDropKey(sessionIdHex);
    expect(deadDrop.ipnsName).not.toBe(computeIpnsName(sessionIdHex));
  });

  it('sempre começa com o prefixo multibase base36 "k"', () => {
    expect(deriveDeadDropKey(sessionIdHex).ipnsName.startsWith('k')).toBe(true);
  });
});

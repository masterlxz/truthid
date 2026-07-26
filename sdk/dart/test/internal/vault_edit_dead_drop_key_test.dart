import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/vault_edit_dead_drop_key.dart';
import 'package:web3dart/crypto.dart' show bytesToHex;

void main() {
  // Mesmo sessionIdHex de fixture de ipns_key_test.dart, mas com salt/info
  // domain-separados — o valor abaixo foi calculado rodando
  // extension/src/vaultEdit/deadDropIpnsKey.ts (o encoding
  // protobuf/multihash/CID/base36 em si já foi validado contra um Kubo
  // 0.42.0 real pelo fixture do namespace de leitura, aqui só muda o
  // material de entrada do HKDF). Precisa bater byte-a-byte com
  // extension/src/vaultEdit/deadDropIpnsKey.test.ts e
  // mobile/test/services/vault_edit_dead_drop_ipns_key_service_test.dart.
  const testSessionIdHex = '000102030405060708090a0b0c0d0e0f';
  const expectedIpnsName = 'k51qzi5uqu5djgtmynxex3q39osopskdt54vg2txhdkfjcwo1114qqv9n9uld9';
  const expectedPrivateKeyProtobufHex =
      '08011240013d3d93709cf05c51ae0854cca8195e81585a474f91d4b19d644464fabfbb4883c5a3bfbd2b79f05f99e265b690145687f74d6f76aeffdd3aacd4ba52447cad';

  test('matches the vector computed from the TypeScript reference', () async {
    final key = await deriveVaultEditDeadDropKey(testSessionIdHex);
    expect(key.ipnsName, expectedIpnsName);
    expect(bytesToHex(key.privateKeyProtobuf), expectedPrivateKeyProtobufHex);
  });

  test('is deterministic — same sessionId always derives the same keypair', () async {
    final a = await deriveVaultEditDeadDropKey(testSessionIdHex);
    final b = await deriveVaultEditDeadDropKey(testSessionIdHex);
    expect(a.ipnsName, b.ipnsName);
    expect(a.privateKeyProtobuf, b.privateKeyProtobuf);
  });

  test('different sessionIds derive different keypairs', () async {
    final a = await deriveVaultEditDeadDropKey(testSessionIdHex);
    final b = await deriveVaultEditDeadDropKey('0f0e0d0c0b0a09080706050403020100');
    expect(a.ipnsName, isNot(b.ipnsName));
  });

  test('derives a different name than the read-pairing namespace (domain separation)', () async {
    final deadDrop = await deriveVaultEditDeadDropKey(testSessionIdHex);
    // k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh — mesmo
    // sessionId, namespace de leitura (ipns_key_test.dart).
    expect(deadDrop.ipnsName, isNot('k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh'));
  });

  test('always starts with the "k" multibase prefix', () async {
    final key = await deriveVaultEditDeadDropKey(testSessionIdHex);
    expect(key.ipnsName, startsWith('k'));
  });
}

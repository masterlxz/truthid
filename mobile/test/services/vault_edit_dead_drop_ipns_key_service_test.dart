import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/ipns_key_service.dart' as read_flow;
import 'package:truthid_mobile/services/vault_edit_dead_drop_ipns_key_service.dart';

void main() {
  // Mesmo sessionId de fixture usado em `ipns_key_service_test.dart`, mas o
  // nome esperado abaixo veio de `extension/src/vaultEdit/
  // deadDropIpnsKey.test.ts` (vetor cruzado TS -> Dart, mesmo padrão rigoroso
  // já usado pro cipher do vault-edit na Sessão 135) — bate byte-a-byte
  // porque os dois lados usam o mesmo salt/info HKDF domain-separados
  // ("TruthID Vault Edit IPNS"/"dead-drop-key-v1") e a mesma codificação
  // protobuf/multihash/CID/base36 já validada contra Kubo real pelo
  // namespace irmão (leitura do vault).
  const testSessionIdHex = '000102030405060708090a0b0c0d0e0f';
  const expectedIpnsName =
      'k51qzi5uqu5djgtmynxex3q39osopskdt54vg2txhdkfjcwo1114qqv9n9uld9';

  test('computeIpnsNameForSession bate com o vetor cruzado da extensão',
      () async {
    final name = await computeIpnsNameForSession(testSessionIdHex);
    expect(name, expectedIpnsName);
  });

  test('é determinístico', () async {
    final a = await computeIpnsNameForSession(testSessionIdHex);
    final b = await computeIpnsNameForSession(testSessionIdHex);
    expect(a, b);
  });

  test('sessionIds diferentes derivam nomes diferentes', () async {
    final a = await computeIpnsNameForSession(testSessionIdHex);
    final b = await computeIpnsNameForSession('0f0e0d0c0b0a09080706050403020100');
    expect(a, isNot(b));
  });

  test('difere do namespace de leitura do vault (domain separation)', () async {
    final editName = await computeIpnsNameForSession(testSessionIdHex);
    final readFlowKey = await read_flow.deriveIpnsDeadDropKey(testSessionIdHex);
    expect(editName, isNot(readFlowKey.ipnsName));
  });

  test('sempre começa com o prefixo multibase base36 "k"', () async {
    final name = await computeIpnsNameForSession(testSessionIdHex);
    expect(name.startsWith('k'), isTrue);
  });
}

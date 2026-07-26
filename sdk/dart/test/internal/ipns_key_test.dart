import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/ipns_key.dart';

void main() {
  // Same fixed sessionId as mobile/test/services/ipns_key_service_test.dart —
  // validated against a real Kubo 0.42.0 node (not just internal
  // round-trip): the private key derived from this sessionId was actually
  // imported via `POST /api/v0/key/import?format=libp2p-protobuf-cleartext`,
  // and the `Id` Kubo returned matched this exact IPNS name byte-for-byte.
  const testSessionIdHex = '000102030405060708090a0b0c0d0e0f';
  const expectedIpnsName =
      'k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh';

  test('matches the fixture validated against a real Kubo node', () async {
    final name = await deriveDeadDropIpnsName(testSessionIdHex);
    expect(name, expectedIpnsName);
  });

  test('is deterministic — same sessionId always derives the same name', () async {
    final a = await deriveDeadDropIpnsName(testSessionIdHex);
    final b = await deriveDeadDropIpnsName(testSessionIdHex);
    expect(a, b);
  });

  test('different sessionIds derive different IPNS names', () async {
    final a = await deriveDeadDropIpnsName('000102030405060708090a0b0c0d0e0f');
    final b = await deriveDeadDropIpnsName('0f0e0d0c0b0a09080706050403020100');
    expect(a, isNot(b));
  });

  test('always starts with the "k" multibase prefix', () async {
    final name = await deriveDeadDropIpnsName(testSessionIdHex);
    expect(name, startsWith('k'));
  });
}

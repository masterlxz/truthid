import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/ecies.dart';

void main() {
  final ecies = EciesService();

  test('round-trips a message: encrypt then decrypt recovers the plaintext', () async {
    final keyPair = ecies.generateKeyPair();
    final plaintext = Uint8List.fromList('hello truthid'.codeUnits);

    final blob = await ecies.encrypt(plaintext, keyPair.publicKeyHex);
    final decrypted = await ecies.decrypt(blob, keyPair.privateKeyBytes);

    expect(decrypted, plaintext);
  });

  test('produces a different blob on every call (fresh ephemeral key + nonce)', () async {
    final keyPair = ecies.generateKeyPair();
    final plaintext = Uint8List.fromList('same message'.codeUnits);

    final blob1 = await ecies.encrypt(plaintext, keyPair.publicKeyHex);
    final blob2 = await ecies.encrypt(plaintext, keyPair.publicKeyHex);

    expect(blob1, isNot(blob2));
  });

  test('decrypting with the wrong private key fails', () async {
    final keyPair = ecies.generateKeyPair();
    final wrongKeyPair = ecies.generateKeyPair();
    final plaintext = Uint8List.fromList('secret'.codeUnits);

    final blob = await ecies.encrypt(plaintext, keyPair.publicKeyHex);

    expect(
      () => ecies.decrypt(blob, wrongKeyPair.privateKeyBytes),
      throwsA(anything),
    );
  });

  test('rejects a blob shorter than the minimum valid size', () async {
    final keyPair = ecies.generateKeyPair();
    expect(
      () => ecies.decrypt(Uint8List(10), keyPair.privateKeyBytes),
      throwsArgumentError,
    );
  });

  test('generateKeyPair produces a valid compressed public key hex', () {
    final keyPair = ecies.generateKeyPair();
    expect(keyPair.publicKeyHex, matches(RegExp(r'^(02|03)[0-9a-f]{64}$')));
    expect(keyPair.privateKeyBytes, hasLength(32));
  });
}

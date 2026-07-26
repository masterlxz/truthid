import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/pin_content_cipher.dart';

void main() {
  const sessionId = '000102030405060708090a0b0c0d0e0f';

  test('derivePinContentKey is deterministic for the same sessionId', () {
    expect(derivePinContentKey(sessionId), derivePinContentKey(sessionId));
  });

  test('derivePinContentKey differs from a different sessionId', () {
    expect(
      derivePinContentKey(sessionId),
      isNot(derivePinContentKey('0f0e0d0c0b0a09080706050403020100')),
    );
  });

  test('encryptPinContent produces a genuinely decryptable AES-256-GCM blob', () async {
    final key = derivePinContentKey(sessionId);
    final plaintext = Uint8List.fromList('file contents to pin'.codeUnits);

    final blob = await encryptPinContent(plaintext, key);

    // Manually unpack the blob the same way the mobile's phase-1 receiver
    // does (nonce(12) || ciphertext || tag(16)) and decrypt with the raw
    // `cryptography` package, independent of any SDK decrypt helper —
    // proves the blob is a real, valid AES-GCM ciphertext, not just
    // internally self-consistent.
    final nonce = blob.sublist(0, 12);
    final rest = blob.sublist(12);
    final mac = rest.sublist(rest.length - 16);
    final ciphertext = rest.sublist(0, rest.length - 16);

    final decrypted = await AesGcm.with256bits().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
    );

    expect(Uint8List.fromList(decrypted), plaintext);
  });

  test('produces a different blob on every call (fresh nonce)', () async {
    final key = derivePinContentKey(sessionId);
    final plaintext = Uint8List.fromList('same content'.codeUnits);

    final blob1 = await encryptPinContent(plaintext, key);
    final blob2 = await encryptPinContent(plaintext, key);

    expect(blob1, isNot(blob2));
  });
}

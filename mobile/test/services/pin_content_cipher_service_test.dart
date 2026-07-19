import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/pin_content_cipher_service.dart';

void main() {
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';

  test('derivePinContentKey é determinístico e sempre tem 32 bytes',
      () async {
    final a = derivePinContentKey(sessionIdHex);
    final b = derivePinContentKey(sessionIdHex);
    expect(a, b);
    expect(a.length, 32);
  });

  test('sessionIds diferentes derivam chaves diferentes', () async {
    final a = derivePinContentKey(sessionIdHex);
    final b = derivePinContentKey('0f0e0d0c0b0a09080706050403020100');
    expect(a, isNot(b));
  });

  test('encrypt+decrypt faz round-trip com o conteúdo original', () async {
    final key = derivePinContentKey(sessionIdHex);
    final plaintext =
        Uint8List.fromList(utf8.encode('{"site":"example.com"}'));

    final blob = await encryptPinContent(plaintext, key);
    final decrypted = await decryptPinContent(blob, key);

    expect(decrypted, plaintext);
  });

  test('decrypt com a chave errada lança FormatException', () async {
    final key = derivePinContentKey(sessionIdHex);
    final wrongKey = derivePinContentKey('0f0e0d0c0b0a09080706050403020100');
    final blob = await encryptPinContent(
      Uint8List.fromList([1, 2, 3]),
      key,
    );

    expect(
      () => decryptPinContent(blob, wrongKey),
      throwsA(isA<FormatException>()),
    );
  });

  test('decrypt de um blob corrompido lança FormatException', () async {
    final key = derivePinContentKey(sessionIdHex);
    final blob = await encryptPinContent(
      Uint8List.fromList([1, 2, 3]),
      key,
    );
    blob[blob.length - 1] ^= 0xff; // corrompe o último byte do MAC

    expect(
      () => decryptPinContent(blob, key),
      throwsA(isA<FormatException>()),
    );
  });

  test('decrypt de um blob curto demais lança FormatException', () async {
    final key = derivePinContentKey(sessionIdHex);
    expect(
      () => decryptPinContent(Uint8List.fromList([1, 2, 3]), key),
      throwsA(isA<FormatException>()),
    );
  });
}

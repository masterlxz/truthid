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

  // Vetor cruzado: o mesmo blob gerado por este teste (via
  // tool/pin_content_cipher_fixture.dart) está hardcoded em
  // desktop-src-tauri/src/pin_content_cipher.rs (Practice Valuation),
  // provando que os dois lados derivam a mesma chave e usam o mesmo layout
  // de blob (nonce||ciphertext+tag) sem precisar de um celular físico.
  test('decifra o fixture cruzado usado no lado requisitante (Rust)',
      () async {
    final key = derivePinContentKey(sessionIdHex);
    final blobHex =
        'b23757d2e7de00df20298fa375385826e472958faa49cd2320c8694c7770'
        'e7a6415cf7d6a6b72ae251e79001cb9b1dc4eb57f2b9fcdd2c';
    final blob = Uint8List.fromList(
      List<int>.generate(
        blobHex.length ~/ 2,
        (i) => int.parse(blobHex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );

    final decrypted = await decryptPinContent(blob, key);

    expect(utf8.decode(decrypted), 'truthid-pin-content-fixture');
  });
}

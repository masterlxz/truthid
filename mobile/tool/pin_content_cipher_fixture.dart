// Script único, não faz parte do app — gera o vetor cruzado real usado no
// teste Rust `decrypts_a_fixture_encrypted_by_the_real_dart_side`
// (Practice Valuation, pin_content_cipher.rs) e no teste Dart espelho
// (test/services/pin_content_cipher_service_test.dart). Rodar com:
//   ./dev.sh dart run tool/pin_content_cipher_fixture.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart' show bytesToHex;

import '../lib/services/pin_content_cipher_service.dart';

Future<void> main() async {
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';
  final plaintext =
      Uint8List.fromList(utf8.encode('truthid-pin-content-fixture'));

  final key = derivePinContentKey(sessionIdHex);
  final blob = await encryptPinContent(plaintext, key);

  // Prova de round-trip antes de imprimir — se isso falhar, o fixture abaixo
  // estaria quebrado.
  final decrypted = await decryptPinContent(blob, key);
  if (!listsEqual(decrypted, plaintext)) {
    throw StateError('round-trip check failed, fixture would be invalid');
  }

  print('sessionIdHex: $sessionIdHex');
  print('keyHex: ${bytesToHex(key)}');
  print('plaintextUtf8: ${utf8.decode(plaintext)}');
  print('blobHex: ${bytesToHex(blob)}');
}

bool listsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

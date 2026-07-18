import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/backup_cipher_service.dart';

void main() {
  late BackupCipherService cipher;

  setUp(() {
    cipher = BackupCipherService();
  });

  test('roundtrip com salt/nonce aleatórios (encrypt/decrypt públicos)', () async {
    final plaintext = Uint8List.fromList(utf8.encode('{"version":1,"entries":[]}'));
    final blob = await cipher.encrypt(plaintext, 'hunter2');
    final decrypted = await cipher.decrypt(blob, 'hunter2');
    expect(utf8.decode(decrypted), '{"version":1,"entries":[]}');
  });

  test('duas chamadas de encrypt() produzem blobs diferentes (salt/nonce aleatórios)', () async {
    final plaintext = Uint8List.fromList(utf8.encode('same'));
    final blob1 = await cipher.encrypt(plaintext, 'hunter2');
    final blob2 = await cipher.encrypt(plaintext, 'hunter2');
    expect(blob1, isNot(equals(blob2)));
  });

  test('senha errada lança FormatException', () async {
    final plaintext = Uint8List.fromList(utf8.encode('sensitive'));
    final blob = await cipher.encrypt(plaintext, 'senha-certa');
    expect(() => cipher.decrypt(blob, 'senha-errada'), throwsFormatException);
  });

  test('blob adulterado lança FormatException', () async {
    final plaintext = Uint8List.fromList(utf8.encode('sensitive'));
    final blob = await cipher.encrypt(plaintext, 'hunter2');
    blob[blob.length - 1] ^= 0xFF;
    expect(() => cipher.decrypt(blob, 'hunter2'), throwsFormatException);
  });

  test('magic errado lança FormatException com mensagem clara', () async {
    final plaintext = Uint8List.fromList(utf8.encode('sensitive'));
    final blob = await cipher.encrypt(plaintext, 'hunter2');
    blob[0] ^= 0xFF;
    await expectLater(
      cipher.decrypt(blob, 'hunter2'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('bad magic'))),
    );
  });

  test('blob muito curto lança FormatException', () async {
    expect(
      () => cipher.decrypt(Uint8List(10), 'hunter2'),
      throwsFormatException,
    );
  });

  // Vetor fixo cruzado byte-a-byte com
  // desktop/src-tauri/src/backup.rs::tests::fixed_vector_matches_dart —
  // mesma senha, salt, iterations (baixo de propósito, só pra teste) e nonce
  // dos dois lados. Prova que os dois lados produzem exatamente o mesmo blob.
  test('vetor fixo bate byte-a-byte com o Rust', () async {
    const password = 'cross-language-test-vector';
    final salt = Uint8List.fromList(List.generate(16, (i) => i + 1)); // 0x01..0x10
    final nonce = Uint8List.fromList(List.generate(12, (i) => 0x20 + i)); // 0x20..0x2b
    const iterations = 100;
    final plaintext = Uint8List.fromList(utf8.encode('{"version":1,"entries":[]}'));

    final blob = await cipher.encryptWith(
      plaintext,
      password,
      salt: salt,
      nonce: nonce,
      iterations: iterations,
    );

    expect(
      _hex(blob),
      '544944564c5442310102030405060708090a0b0c0d0e0f1000000064202122232425262728292a2b'
      '4aa17c8e8b6eefe955e8f4e0d999dec4058c226c174dbc07c671120e5225cd39d4910240919fe9d309a9',
    );
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

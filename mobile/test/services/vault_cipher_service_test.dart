import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/services/vault_key_service.dart';
import 'package:truthid_mobile/services/vault_cipher_service.dart';

class MockVaultKeyService extends Mock implements VaultKeyService {}

void main() {
  late MockVaultKeyService mockKeyService;
  late VaultCipherService cipher;

  // Chave AES-256 fixa para testes (nunca usada em produção)
  final testKey = Uint8List.fromList(List.generate(32, (i) => i));

  setUp(() {
    mockKeyService = MockVaultKeyService();
    when(() => mockKeyService.deriveVaultKey())
        .thenAnswer((_) async => testKey);
    cipher = VaultCipherService(keyService: mockKeyService);
  });

  group('VaultCipherService', () {
    test('roundtrip — texto vazio', () async {
      final blob = await cipher.encrypt(Uint8List(0));
      final plain = await cipher.decrypt(blob);
      expect(plain, isEmpty);
    });

    test('roundtrip — JSON de entrada de vault', () async {
      final original = utf8.encode(
        '{"site":"github.com","user":"fab","password":"s3cr3t"}',
      );
      final blob = await cipher.encrypt(Uint8List.fromList(original));
      final plain = await cipher.decrypt(blob);
      expect(plain, equals(original));
    });

    test('roundtrip — dados binários arbitrários', () async {
      final original = Uint8List.fromList(List.generate(256, (i) => i));
      final blob = await cipher.encrypt(original);
      final plain = await cipher.decrypt(blob);
      expect(plain, equals(original));
    });

    test('nonce distinto a cada encrypt — mesmo plaintext gera blobs diferentes', () async {
      final plain = Uint8List.fromList(utf8.encode('mesmo texto'));
      final blob1 = await cipher.encrypt(plain);
      final blob2 = await cipher.encrypt(plain);
      expect(blob1, isNot(equals(blob2)));
      // Mas ambos decifram corretamente
      expect(await cipher.decrypt(blob1), equals(plain));
      expect(await cipher.decrypt(blob2), equals(plain));
    });

    test('formato do blob — nonce ocupa primeiros 12 bytes', () async {
      final plain = Uint8List.fromList(utf8.encode('hello'));
      final blob = await cipher.encrypt(plain);
      // nonce(12) + ciphertext(5) + tag(16) = 33
      expect(blob.length, 33);
    });

    test('blob adulterado falha na autenticação', () async {
      final plain = Uint8List.fromList(utf8.encode('sensitive'));
      final blob = await cipher.encrypt(plain);
      final tampered = Uint8List.fromList(blob);
      tampered[15] ^= 0xFF; // corrompe um byte do ciphertext
      expect(() => cipher.decrypt(tampered), throwsA(anything));
    });

    test('blob muito curto lança ArgumentError', () async {
      final short = Uint8List.fromList(List.generate(10, (i) => i));
      expect(
        () => cipher.decrypt(short),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('chave errada falha na autenticação', () async {
      final plain = Uint8List.fromList(utf8.encode('secret'));
      final blob = await cipher.encrypt(plain);

      // Substitui a chave por outra
      final otherKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
      when(() => mockKeyService.deriveVaultKey())
          .thenAnswer((_) async => otherKey);

      expect(() => cipher.decrypt(blob), throwsA(anything));
    });
  });
}

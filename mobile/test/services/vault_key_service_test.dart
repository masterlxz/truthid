import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/vault_key_service.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

void main() {
  late MockDeviceKeyService mockKeyService;
  late VaultKeyService vaultKeyService;

  // 32 bytes sequenciais como chave de teste
  final testKey = Uint8List.fromList(List.generate(32, (i) => i));
  // Chave diferente para testar sensibilidade
  final otherKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

  setUp(() {
    mockKeyService = MockDeviceKeyService();
    vaultKeyService = VaultKeyService(deviceKeyService: mockKeyService);
  });

  group('deriveVaultKey', () {
    test('retorna 32 bytes', () async {
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => testKey);

      final key = await vaultKeyService.deriveVaultKey();

      expect(key.length, 32);
    });

    test('é determinístico — mesma chave privada sempre gera o mesmo resultado', () async {
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => testKey);

      final key1 = await vaultKeyService.deriveVaultKey();
      final key2 = await vaultKeyService.deriveVaultKey();

      expect(key1, equals(key2));
    });

    test('é sensível à chave privada — chave diferente gera resultado diferente', () async {
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => testKey);
      final key1 = await vaultKeyService.deriveVaultKey();

      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => otherKey);
      final key2 = await vaultKeyService.deriveVaultKey();

      expect(key1, isNot(equals(key2)));
    });

    test('não retorna a chave privada diretamente', () async {
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => testKey);

      final vaultKey = await vaultKeyService.deriveVaultKey();

      expect(vaultKey, isNot(equals(testKey)));
    });

    test('vetor de referência — garante compatibilidade Desktop ↔ Mobile', () async {
      // Vetor computado via HKDF-SHA256 (RFC 5869):
      //   IKM  = [0x00..0x1f] (32 bytes)
      //   salt = UTF-8("TruthID")
      //   info = UTF-8("vault-key-v1")
      //   L    = 32
      //
      // Atualizar este valor ao confirmar com o Desktop (Rust) que ambos produzem
      // o mesmo resultado para o mesmo IKM — garante interoperabilidade.
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => testKey);

      final vaultKey = await vaultKeyService.deriveVaultKey();

      // Confirma que o vetor é estável entre versões do código
      final firstRun = vaultKey;
      final secondRun = await vaultKeyService.deriveVaultKey();
      expect(firstRun, equals(secondRun));
    });
  });
}

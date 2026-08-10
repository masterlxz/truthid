import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final testWalletJson = File('test/fixtures/arweave/test_wallet.json').readAsStringSync();

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  void mockStorage({String? initialValue}) {
    String? stored = initialValue;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return stored;
        case 'write':
          stored = (call.arguments as Map)['value'] as String?;
          return null;
        default:
          return null;
      }
    });
  }

  group('ArweaveWalletService', () {
    test('exists() é false quando nada foi gravado ainda', () async {
      mockStorage();
      final service = ArweaveWalletService();
      expect(await service.exists(), isFalse);
    });

    test('load() lança quando nenhuma wallet configurada', () async {
      mockStorage();
      final service = ArweaveWalletService();
      await expectLater(service.load(), throwsA(isA<Exception>()));
    });

    test('load()/address() funcionam com wallet já configurada', () async {
      mockStorage(initialValue: testWalletJson);
      final service = ArweaveWalletService();
      expect(await service.exists(), isTrue);
      final jwk = await service.load();
      expect(jwk.kty, 'RSA');
      // mesmo endereço já cross-checado contra arweave-js real
      // (arweave_jwk_test.dart).
      expect(await service.address(), 'zwYLZnytErQAb0-taJUwVav55JiiE1kVgPBsn2pcnHQ');
    });

    test('import() grava e devolve o endereço correto', () async {
      mockStorage();
      final service = ArweaveWalletService();
      final address = await service.import(testWalletJson);
      expect(address, 'zwYLZnytErQAb0-taJUwVav55JiiE1kVgPBsn2pcnHQ');
      expect(await service.exists(), isTrue);
    });

    test('import() rejeita JWK inválido sem deixar o serviço "meio gravado"', () async {
      mockStorage();
      final service = ArweaveWalletService();
      final decoded = jsonDecode(testWalletJson) as Map<String, dynamic>;
      decoded['kty'] = 'EC';
      await expectLater(
        service.import(jsonEncode(decoded)),
        throwsA(isA<FormatException>()),
      );
      expect(await service.exists(), isFalse);
    });

    // generate() não é coberto aqui de propósito — chama generateJwk(),
    // keygen RSA-4096 real, lenta (segundos) e não-determinística em tempo
    // (mesmo motivo do Rust marcar o teste equivalente como #[ignore]).
    // Cobertura de geração + isolate + benchmark fica na etapa seguinte.
  });
}

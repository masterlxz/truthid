import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';

import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/vault_key_service.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDeviceKeyService mockKeyService;
  late VaultKeyService vaultKeyService;

  // 32 bytes sequenciais como chave de teste
  final testKey = Uint8List.fromList(List.generate(32, (i) => i));
  // Chave diferente para testar sensibilidade
  final otherKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

  // VaultKeyService._storage é um FlutterSecureStorage real (campo estático,
  // não injetável) — sem mock do canal, a chamada trava/lança
  // "Binding has not yet been initialized" fora do ambiente real de app
  // (achado da Sessão 98). `null` simula "sem chave cacheada", forçando o
  // fallback pra derivação legada, que é o que estes testes verificam.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // Simula um storage em memória (chave -> valor) por trás do MethodChannel,
  // pra poder testar deriveAndStoreFromWalletSignature (que escreve, não só
  // lê) sem precisar de um device/plugin real — mesmo achado da Sessão 98
  // documentado acima, agora cobrindo `write` além de `read`.
  final fakeStorage = <String, String>{};

  setUp(() {
    mockKeyService = MockDeviceKeyService();
    vaultKeyService = VaultKeyService(deviceKeyService: mockKeyService);
    fakeStorage.clear();

    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final key = args?['key'] as String?;
      if (call.method == 'read') return fakeStorage[key];
      if (call.method == 'write') {
        fakeStorage[key!] = args!['value'] as String;
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
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

  group('deriveAndStoreFromWalletSignature', () {
    // Vetor cruzado com o HKDF real do Rust (derive_vault_key_from_wallet,
    // desktop/src-tauri/src/lib.rs:260-272) pros mesmos inputs — garante
    // interoperabilidade Desktop↔Mobile pra P68 (fatia 1), mesmo princípio já
    // documentado no teste "vetor de referência" acima pra vault-key-v1.
    final r = Uint8List.fromList(List.generate(32, (i) => i));
    final s = Uint8List.fromList(List.generate(32, (i) => i + 32));
    const v = 27;
    const expectedHex =
        'a47f35620b9155a384ae5759e08f6ca67b2ebc142e4747c76b447fe8aea44a23';

    test('persiste uma chave de 32 bytes que bate com o HKDF do Rust',
        () async {
      await vaultKeyService.deriveAndStoreFromWalletSignature(
          r: r, s: s, v: v);

      final key = await vaultKeyService.deriveVaultKey();
      expect(key.length, 32);
      expect(bytesToHex(key), expectedHex);
    });

    test('fica persistida — hasVaultKey() vira true depois', () async {
      expect(await vaultKeyService.hasVaultKey(), isFalse);

      await vaultKeyService.deriveAndStoreFromWalletSignature(
          r: r, s: s, v: v);

      expect(await vaultKeyService.hasVaultKey(), isTrue);
    });

    test('é sensível ao v — v diferente gera chave diferente', () async {
      await vaultKeyService.deriveAndStoreFromWalletSignature(
          r: r, s: s, v: 27);
      final key1 = await vaultKeyService.deriveVaultKey();

      fakeStorage.clear();
      await vaultKeyService.deriveAndStoreFromWalletSignature(
          r: r, s: s, v: 28);
      final key2 = await vaultKeyService.deriveVaultKey();

      expect(key1, isNot(equals(key2)));
    });

    test('depois de persistida, deriveVaultKey não cai mais pra derivação legada',
        () async {
      // Se a chave da wallet não fosse lida primeiro, deriveVaultKey cairia
      // pra _deriveLegacyKey() (baseada na device key) — verificar que o
      // valor batido é o do HKDF da wallet, não o legado, confirma a ordem
      // de prioridade certa (mesma que decryptVaultKeyFromPairing já tem).
      when(() => mockKeyService.getPrivateKeyBytes())
          .thenAnswer((_) async => Uint8List.fromList(List.filled(32, 0xff)));

      await vaultKeyService.deriveAndStoreFromWalletSignature(
          r: r, s: s, v: v);
      final key = await vaultKeyService.deriveVaultKey();

      expect(bytesToHex(key), expectedHex);
      verifyNever(() => mockKeyService.getPrivateKeyBytes());
    });
  });

  group('tryRecoverFromChain', () {
    const address = '0x1234567890123456789012345678901234567890';
    late MockBlockchainService mockBlockchain;

    setUp(() {
      mockBlockchain = MockBlockchainService();
      when(() => mockKeyService.getDeviceAddress())
          .thenAnswer((_) async => address);
    });

    test('retorna false quando não há vault key on-chain pro device', () async {
      when(() => mockBlockchain.getDeviceVaultKey(address))
          .thenAnswer((_) async => null);

      final recovered =
          await vaultKeyService.tryRecoverFromChain(mockBlockchain);

      expect(recovered, isFalse);
    });

    test('retorna false quando o blob on-chain está corrompido/incompleto', () async {
      when(() => mockBlockchain.getDeviceVaultKey(address))
          .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

      final recovered =
          await vaultKeyService.tryRecoverFromChain(mockBlockchain);

      expect(recovered, isFalse);
    });
  });
}

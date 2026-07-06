import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';

import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/ipfs_gateway_client.dart';
import 'package:truthid_mobile/services/vault_cipher_service.dart';
import 'package:truthid_mobile/services/vault_key_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';
import 'package:truthid_mobile/services/vault_sync_service.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockIpfsGatewayClient extends Mock implements IpfsGatewayClient {}

class MockVaultKeyService extends Mock implements VaultKeyService {}

// Cipher no-op — mesma técnica de vault_repository_test.dart, testa a lógica
// de sync sem depender de chave real.
class _FakeCipherService extends VaultCipherService {
  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async => plaintext;
  @override
  Future<Uint8List> decrypt(Uint8List blob) async => blob;
}

Uint8List _plaintextBlob(List<Map<String, dynamic>> entries) {
  final json = jsonEncode({'version': 1, 'entries': entries});
  return Uint8List.fromList(utf8.encode(json));
}

Map<String, dynamic> _entry(String site) => {
      'id': 'e-$site',
      'site': site,
      'url': '',
      'username': 'u',
      'password': 'p',
      'notes': '',
      'profiles': <String>[],
      'created_at': 1700000000,
      'updated_at': 1700000000,
    };

void main() {
  late MockBlockchainService mockBlockchain;
  late MockIpfsGatewayClient mockGateway;
  late MockVaultKeyService mockKeyService;
  late Directory tempDir;
  late String vaultPath;
  late VaultRepository repository;
  late VaultSyncService syncService;

  final identityId = BigInt.one;
  final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  final wrongHash =
      bytesToHex(Uint8List.fromList(List.filled(32, 0xff)), include0x: true);

  setUpAll(() {
    registerFallbackValue(BigInt.one);
  });

  setUp(() async {
    mockBlockchain = MockBlockchainService();
    mockGateway = MockIpfsGatewayClient();
    mockKeyService = MockVaultKeyService();
    tempDir = await Directory.systemTemp.createTemp('vault_sync_test_');
    vaultPath = '${tempDir.path}/vault.enc';
    repository = VaultRepository(
      cipherService: _FakeCipherService(),
      testPath: vaultPath,
    );
    syncService = VaultSyncService(
      blockchainService: mockBlockchain,
      gatewayClient: mockGateway,
      vaultKeyService: mockKeyService,
      repository: repository,
    );

    when(() => mockKeyService.hasVaultKey()).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('sem vault key — retorna noVaultKey sem chamar rede', () async {
    when(() => mockKeyService.hasVaultKey()).thenAnswer((_) async => false);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.noVaultKey);
    expect(outcome.entries, isEmpty);
    verifyNever(() => mockBlockchain.hasVault(any()));
    verifyNever(() => mockGateway.fetch(any()));
  });

  test('hasVault == false — retorna noVaultPublished', () async {
    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => false);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.noVaultPublished);
    expect(outcome.entries, isEmpty);
  });

  test('hash bate — grava cache e retorna synced com as entradas decifradas',
      () async {
    final bytes = _plaintextBlob([_entry('example.com')]);
    final digest = bytesToHex(keccak256(bytes), include0x: true);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyTestCid',
            contentHashHex: digest,
            updatedAt: updatedAt,
            version: 1));
    when(() => mockGateway.fetch('bafyTestCid')).thenAnswer((_) async => bytes);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.synced);
    expect(outcome.entries, hasLength(1));
    expect(outcome.entries.first.site, 'example.com');
    expect(await File(vaultPath).readAsBytes(), equals(bytes));
  });

  test(
      'hash não bate e não há cache prévio — syncFailedNoCache, nada é gravado',
      () async {
    final bytes = _plaintextBlob([_entry('example.com')]);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyTestCid',
            contentHashHex: wrongHash,
            updatedAt: updatedAt,
            version: 1));
    when(() => mockGateway.fetch('bafyTestCid')).thenAnswer((_) async => bytes);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.syncFailedNoCache);
    expect(outcome.entries, isEmpty);
    expect(await File(vaultPath).exists(), isFalse);
  });

  test(
      'hash não bate mas há cache prévio — offlineUsingCache, cache antigo preservado',
      () async {
    // Popula um cache "válido" primeiro, de uma sincronização anterior.
    final cachedBytes = _plaintextBlob([_entry('example.com')]);
    await repository.overwriteCache(cachedBytes);

    final badBytes = _plaintextBlob([_entry('malicious.com')]);
    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyTestCid',
            contentHashHex: wrongHash,
            updatedAt: updatedAt,
            version: 2));
    when(() => mockGateway.fetch('bafyTestCid'))
        .thenAnswer((_) async => badBytes);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.offlineUsingCache);
    expect(outcome.entries, hasLength(1));
    // Cache antigo, não o blob malicioso não verificado.
    expect(outcome.entries.first.site, 'example.com');
    expect(outcome.error, isNotNull);
    expect(await File(vaultPath).readAsBytes(), equals(cachedBytes));
  });

  test('falha de rede em getVault com cache prévio — cai pro cache',
      () async {
    final cachedBytes = _plaintextBlob([_entry('example.com')]);
    await repository.overwriteCache(cachedBytes);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId))
        .thenThrow(Exception('network down'));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.offlineUsingCache);
    expect(outcome.entries, hasLength(1));
  });

  test('falha de rede em hasVault com cache prévio — cai pro cache',
      () async {
    final cachedBytes = _plaintextBlob([_entry('example.com')]);
    await repository.overwriteCache(cachedBytes);

    when(() => mockBlockchain.hasVault(identityId))
        .thenThrow(Exception('network down'));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.offlineUsingCache);
    expect(outcome.entries, hasLength(1));
  });

  test('falha de rede sem cache nenhum — syncFailedNoCache', () async {
    when(() => mockBlockchain.hasVault(identityId))
        .thenThrow(Exception('network down'));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.syncFailedNoCache);
    expect(outcome.entries, isEmpty);
  });
}

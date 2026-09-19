import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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

// Fallback pra `any()`/`captureAny()` sobre parâmetro do tipo
// BlockchainService (usado por `verifyNever(() =>
// mockKeyService.tryRecoverFromChain(any()))`) — nunca é interagido de
// verdade, só precisa existir pro mocktail registrar o tipo.
class _FakeBlockchainService extends Fake implements BlockchainService {}

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

// Cipher que simula rotação de DEK: cada blob leva a etiqueta da chave que o
// cifrou e `decrypt` falha (como o AES-GCM real com chave errada) quando a
// etiqueta não bate com a chave ativa.
class _RotatingCipherService extends VaultCipherService {
  String key = 'K1';

  Uint8List _tag(Uint8List plaintext) =>
      Uint8List.fromList([...utf8.encode('$key:'), ...plaintext]);

  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async => _tag(plaintext);

  @override
  Future<Uint8List> decrypt(Uint8List blob) async {
    final prefix = '$key:';
    final head = blob.length < prefix.length
        ? ''
        : utf8.decode(blob.sublist(0, prefix.length), allowMalformed: true);
    if (head != prefix) throw StateError('authentication failed');
    return Uint8List.sublistView(blob, prefix.length);
  }
}

Uint8List _plaintextBlob(List<Map<String, dynamic>> entries) {
  final json = jsonEncode({'version': 1, 'entries': entries});
  return Uint8List.fromList(utf8.encode(json));
}

// Blob de UMA entrada, no formato que writeEntryBlob/decryptEntryBlob
// produzem/consomem — com _FakeCipherService (passthrough), é só o JSON da
// entrada, sem cifra real por cima (mesma técnica de _plaintextBlob acima,
// que já não cifra o vault inteiro nestes testes).
Uint8List _plaintextEntryBlob(Map<String, dynamic> entryJson) =>
    Uint8List.fromList(utf8.encode(jsonEncode(entryJson)));

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // pendingChanges()/markPublished() do VaultRepository usam
  // FlutterSecureStorage real (campo estático, não injetável) — mesmo mock
  // de vault_publish_service_test.dart (Sessão 98), necessário agora que
  // sync() também chama markPublished() (fix da Sessão 130).
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final fakeSecureStorage = <String, String>{};

  setUpAll(() {
    registerFallbackValue(BigInt.one);
    registerFallbackValue(_FakeBlockchainService());
  });

  setUp(() async {
    fakeSecureStorage.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'write':
          fakeSecureStorage[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'read':
          return fakeSecureStorage[call.arguments['key']];
        default:
          return null;
      }
    });
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
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
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

  test(
      'já tem vault key — reconsulta deviceVaultKeys pra pegar rotação de '
      'DEK feita por outro device (achado do /plan de rotação)', () async {
    when(() => mockKeyService.tryRecoverFromChain(mockBlockchain))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => false);

    await syncService.sync(identityId);

    verify(() => mockKeyService.tryRecoverFromChain(mockBlockchain)).called(1);
  });

  test(
      'reconsulta de deviceVaultKeys falha (offline) — sync segue com a '
      'chave já cacheada, não propaga o erro', () async {
    when(() => mockKeyService.tryRecoverFromChain(mockBlockchain))
        .thenThrow(Exception('network down'));
    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => false);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.noVaultPublished);
  });

  test('sem vault key — não tenta reconsultar deviceVaultKeys', () async {
    when(() => mockKeyService.hasVaultKey()).thenAnswer((_) async => false);

    await syncService.sync(identityId);

    verifyNever(() => mockKeyService.tryRecoverFromChain(any()));
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
    // P51: `ref` já tinha sido lido on-chain quando o hash-check falhou —
    // dá pra saber que o cid é o esquema IPFS legado mesmo sem cache local.
    expect(outcome.legacyIpfsCid, isTrue);
  });

  test(
      'hash não bate, cid já no Arweave e não há cache prévio — syncFailedNoCache sem sinalizar legado',
      () async {
    final bytes = _plaintextBlob([_entry('example.com')]);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'ar://someArweaveTxId',
            contentHashHex: wrongHash,
            updatedAt: updatedAt,
            version: 1));
    when(() => mockGateway.fetch('ar://someArweaveTxId'))
        .thenAnswer((_) async => bytes);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.syncFailedNoCache);
    // Prova que a detecção do P51 é real (olha o prefixo do cid), não um
    // `true` incondicional assim que `ref` existe.
    expect(outcome.legacyIpfsCid, isFalse);
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

  test(
      'cache local à frente do on-chain (mudanças pendentes não publicadas) — '
      'não sobrescreve nem busca no IPFS', () async {
    // Simula 2 edições locais feitas neste device, nunca publicadas.
    await repository.addEntry(site: 'local-only.com', username: 'u', password: 'p');
    await repository.addEntry(site: 'local-only-2.com', username: 'u', password: 'p');
    final localBlobBefore = await File(vaultPath).readAsBytes();

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    // On-chain está na versão 1 — atrás das 2 edições locais (version 2).
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyOldCid',
            contentHashHex: wrongHash,
            updatedAt: updatedAt,
            version: 1));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.synced);
    expect(outcome.entries.map((e) => e.site),
        containsAll(['local-only.com', 'local-only-2.com']));
    verifyNever(() => mockGateway.fetch(any()));
    expect(await File(vaultPath).readAsBytes(), equals(localBlobBefore));
  });

  test(
      'puxar versão mais nova de outro device marca como publicada — sem '
      '"pending changes" fantasma (bug real, Sessão 130)', () async {
    final bytes = _plaintextBlob([_entry('example.com')]);
    final digest = bytesToHex(keccak256(bytes), include0x: true);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyTestCid',
            contentHashHex: digest,
            updatedAt: updatedAt,
            version: 5));
    when(() => mockGateway.fetch('bafyTestCid')).thenAnswer((_) async => bytes);

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.synced);
    expect(await repository.pendingChanges(), 0);
  });

  test(
      'local já nasce sincronizado com a versão on-chain (ex: recém-pareado) '
      '— marca como publicada, sem esperar um sync mais à frente', () async {
    // Simula um device que recebeu o vault via ECIES no pareamento, com o
    // mesmo conteúdo/versão que já está publicada on-chain, e nunca chamou
    // markPublished() localmente (nunca publicou nada por conta própria).
    final bytes = _plaintextBlob([_entry('example.com')]);
    await repository.overwriteCache(bytes);
    final localVersion = await repository.currentVersion();
    final digest = bytesToHex(keccak256(bytes), include0x: true);

    when(() => mockBlockchain.hasVault(identityId))
        .thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async =>
        VaultRef(
            cid: 'bafyTestCid',
            contentHashHex: digest,
            updatedAt: updatedAt,
            version: localVersion));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.synced);
    verifyNever(() => mockGateway.fetch(any()));
    expect(await repository.pendingChanges(), 0);
  });

  group('Vault por-entrada (manifesto remoto)', () {
    test(
        'cid on-chain aponta pra um manifesto — busca só a entrada referenciada e reconstrói o vault local',
        () async {
      final entryBytes = _plaintextEntryBlob(_entry('example.com'));
      final entryDigest = bytesToHex(keccak256(entryBytes), include0x: true);
      final manifest = VaultManifest(
        version: 1,
        vaultVersion: 1,
        entries: {
          'e-example.com':
              ManifestEntryRef(cid: 'entryCid1', contentHash: entryDigest, updatedAt: 1700000000),
        },
      );
      final manifestBlob = await repository.encryptManifestBlob(manifest);
      final manifestDigest = bytesToHex(keccak256(manifestBlob), include0x: true);

      when(() => mockBlockchain.hasVault(identityId)).thenAnswer((_) async => true);
      when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
          cid: 'ar://manifestTx1',
          contentHashHex: manifestDigest,
          updatedAt: updatedAt,
          version: 1));
      when(() => mockGateway.fetch('ar://manifestTx1')).thenAnswer((_) async => manifestBlob);
      when(() => mockGateway.fetch('entryCid1')).thenAnswer((_) async => entryBytes);

      final outcome = await syncService.sync(identityId);

      expect(outcome.status, VaultSyncStatus.synced);
      expect(outcome.legacyIpfsCid, isFalse);
      expect(outcome.entries, hasLength(1));
      expect(outcome.entries.first.site, 'example.com');
      verify(() => mockGateway.fetch('entryCid1')).called(1);
    });

    test(
        'entrada do manifesto com hash divergente cai no fallback SEM corromper o cache local existente',
        () async {
      // Cache local bom, de uma sincronização anterior — a asserção final
      // (achado rastreado nesta sessão: overwriteCache era chamado
      // incondicionalmente com o blob buscado, mesmo quando era um
      // manifesto que a decifra ia rejeitar logo em seguida) prova que esse
      // bug não pode mais acontecer: o caminho de manifesto nunca chama
      // overwriteCache.
      final goodCache = _plaintextBlob([_entry('good.com')]);
      await repository.overwriteCache(goodCache);

      final entryBytes = _plaintextEntryBlob(_entry('bad-entry.com'));
      final manifest = VaultManifest(
        version: 1,
        vaultVersion: 2,
        entries: {
          'e-bad-entry.com':
              ManifestEntryRef(cid: 'entryCid2', contentHash: wrongHash, updatedAt: 1700000000),
        },
      );
      final manifestBlob = await repository.encryptManifestBlob(manifest);
      final manifestDigest = bytesToHex(keccak256(manifestBlob), include0x: true);

      when(() => mockBlockchain.hasVault(identityId)).thenAnswer((_) async => true);
      when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
          cid: 'ar://manifestTx2',
          contentHashHex: manifestDigest,
          updatedAt: updatedAt,
          version: 2));
      when(() => mockGateway.fetch('ar://manifestTx2')).thenAnswer((_) async => manifestBlob);
      when(() => mockGateway.fetch('entryCid2')).thenAnswer((_) async => entryBytes);

      final outcome = await syncService.sync(identityId);

      expect(outcome.status, VaultSyncStatus.offlineUsingCache);
      expect(outcome.entries, hasLength(1));
      expect(outcome.entries.first.site, 'good.com');
      expect(
        await File(vaultPath).readAsBytes(),
        equals(goodCache),
        reason: 'cache local não pode ser corrompido por uma entrada de manifesto inválida',
      );
    });

    test(
        'manifesto novo com as mesmas entradas de antes — não busca nenhum blob de entrada de novo',
        () async {
      final entryBytes = _plaintextEntryBlob(_entry('example.com'));
      final entryDigest = bytesToHex(keccak256(entryBytes), include0x: true);
      final entryRef =
          ManifestEntryRef(cid: 'entryCid1', contentHash: entryDigest, updatedAt: 1700000000);

      final manifest1 =
          VaultManifest(version: 1, vaultVersion: 1, entries: {'e-example.com': entryRef});
      final manifestBlob1 = await repository.encryptManifestBlob(manifest1);
      final digest1 = bytesToHex(keccak256(manifestBlob1), include0x: true);

      when(() => mockBlockchain.hasVault(identityId)).thenAnswer((_) async => true);
      when(() => mockGateway.fetch('entryCid1')).thenAnswer((_) async => entryBytes);
      when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
          cid: 'ar://manifestTx1',
          contentHashHex: digest1,
          updatedAt: updatedAt,
          version: 1));
      when(() => mockGateway.fetch('ar://manifestTx1')).thenAnswer((_) async => manifestBlob1);

      final first = await syncService.sync(identityId);
      expect(first.status, VaultSyncStatus.synced);

      // 2ª publicação: só profileNames mudou, a entrada continua com o
      // mesmo cid/contentHash de antes.
      final manifest2 = VaultManifest(
        version: 1,
        vaultVersion: 2,
        entries: {'e-example.com': entryRef},
        profileNames: const ['NovoPerfil'],
      );
      final manifestBlob2 = await repository.encryptManifestBlob(manifest2);
      final digest2 = bytesToHex(keccak256(manifestBlob2), include0x: true);
      when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
          cid: 'ar://manifestTx2',
          contentHashHex: digest2,
          updatedAt: updatedAt,
          version: 2));
      when(() => mockGateway.fetch('ar://manifestTx2')).thenAnswer((_) async => manifestBlob2);

      final second = await syncService.sync(identityId);

      expect(second.status, VaultSyncStatus.synced);
      expect(second.entries, hasLength(1));
      expect(second.entries.first.site, 'example.com');
      expect(second.profileNames, ['NovoPerfil']);
      // A entrada não mudou de cid/contentHash — busca-la de novo seria
      // desperdício de rede (e de taxa, do lado de quem publica).
      verify(() => mockGateway.fetch('entryCid1')).called(1);
    });
  });

  test('falha de rede sem cache nenhum — syncFailedNoCache', () async {
    when(() => mockBlockchain.hasVault(identityId))
        .thenThrow(Exception('network down'));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.syncFailedNoCache);
    expect(outcome.entries, isEmpty);
    // `hasVault` falhou antes de `getVault` rodar — sem `ref`, não há como
    // saber se o cid é legado, então não deve sinalizar como tal.
    expect(outcome.legacyIpfsCid, isFalse);
  });

  test(
      'cache local cifrado com a DEK antiga (rotação por outro device, P89) — '
      'separa o cache ilegível e puxa o vault novo do chain em vez de cair no '
      'fallback', () async {
    final cipher = _RotatingCipherService();
    final dir = await Directory('${tempDir.path}/rot').create();
    final rotRepo = VaultRepository(
      cipherService: cipher,
      testPath: '${dir.path}/vault.enc',
    );
    final rotSync = VaultSyncService(
      blockchainService: mockBlockchain,
      gatewayClient: mockGateway,
      vaultKeyService: mockKeyService,
      repository: rotRepo,
    );

    // Estado deste device antes da rotação: vault.enc + manifesto na K1.
    final oldVault = await cipher.encrypt(_plaintextBlob([_entry('old.com')]));
    await rotRepo.overwriteCache(oldVault);
    await rotRepo.saveLastManifest(VaultManifest(
      version: 1,
      vaultVersion: 1,
      entries: {
        'e-old.com': const ManifestEntryRef(
            cid: 'oldCid', contentHash: '0x00', updatedAt: 1700000000),
      },
    ));

    // Outro device rotaciona: este passa a ter a K2 (tryRecoverFromChain) e o
    // Desktop republicou tudo cifrado com a K2.
    cipher.key = 'K2';
    final entryBytes = await cipher.encrypt(_plaintextEntryBlob(_entry('new.com')));
    final entryDigest = bytesToHex(keccak256(entryBytes), include0x: true);
    final manifestBlob = await rotRepo.encryptManifestBlob(VaultManifest(
      version: 1,
      vaultVersion: 2,
      entries: {
        'e-new.com': ManifestEntryRef(
            cid: 'newCid', contentHash: entryDigest, updatedAt: 1700000000),
      },
    ));
    final manifestDigest = bytesToHex(keccak256(manifestBlob), include0x: true);

    when(() => mockBlockchain.hasVault(identityId)).thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
        cid: 'ar://manifestTxRot',
        contentHashHex: manifestDigest,
        updatedAt: updatedAt,
        version: 2));
    when(() => mockGateway.fetch('ar://manifestTxRot'))
        .thenAnswer((_) async => manifestBlob);
    when(() => mockGateway.fetch('newCid')).thenAnswer((_) async => entryBytes);

    final outcome = await rotSync.sync(identityId);

    expect(outcome.status, VaultSyncStatus.synced);
    expect(outcome.entries, hasLength(1));
    expect(outcome.entries.first.site, 'new.com');
    // O vault antigo não foi perdido: fica guardado, byte a byte.
    expect(await File('${dir.path}/vault.enc.unreadable').readAsBytes(),
        equals(oldVault));
  });

  test(
      'ponteiro git: que falha no fetch NÃO é sinalizado como IPFS legado — '
      'senão o banner de migração pra Arweave apareceria pra um vault Git',
      () async {
    when(() => mockBlockchain.hasVault(identityId)).thenAnswer((_) async => true);
    when(() => mockBlockchain.getVault(identityId)).thenAnswer((_) async => VaultRef(
        cid: 'git:AQID@0123456789abcdef0123456789abcdef01234567',
        contentHashHex: wrongHash,
        updatedAt: updatedAt,
        version: 1));
    when(() => mockGateway.fetch(any())).thenThrow(UnsupportedError('git'));

    final outcome = await syncService.sync(identityId);

    expect(outcome.status, VaultSyncStatus.syncFailedNoCache);
    expect(outcome.legacyIpfsCid, isFalse);
  });
}

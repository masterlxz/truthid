import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart' show keccak256, bytesToHex;
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/arweave_client.dart';
import 'package:truthid_mobile/services/session_creator.dart';
import 'package:truthid_mobile/services/vault_cipher_service.dart';
import 'package:truthid_mobile/services/vault_publish_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockArweaveVaultPublisher extends Mock implements ArweaveVaultPublisher {}

class MockSessionCreator extends Mock implements SessionCreator {}

// Cipher no-op — mesmo padrão de vault_repository_test.dart.
class _FakeCipherService extends VaultCipherService {
  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async => plaintext;

  @override
  Future<Uint8List> decrypt(Uint8List blob) async => blob;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VaultRepository repo;
  late MockArweaveVaultPublisher mockArweavePublisher;
  late MockSessionCreator mockSessionCreator;
  late VaultPublishService publishService;

  final smartAccountAddress =
      EthereumAddress.fromHex('0xabababababababababababababababababababab');

  // markPublished()/pendingChanges() do VaultRepository usam
  // FlutterSecureStorage real (campo estático, não injetável) — mockar o
  // canal aqui pelo mesmo motivo de vault_key_service_test.dart (Sessão 98):
  // sem isso, trava/lança "Binding has not yet been initialized" fora do
  // ambiente real de app. Um Map em memória simula o storage real o
  // suficiente pra refletir o valor gravado numa leitura seguinte.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final fakeSecureStorage = <String, String>{};

  setUpAll(() {
    registerFallbackValue(smartAccountAddress);
    registerFallbackValue(Uint8List(0));
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
    tempDir = await Directory.systemTemp.createTemp('vault_publish_test_');
    repo = VaultRepository(
      cipherService: _FakeCipherService(),
      testPath: '${tempDir.path}/vault.enc',
    );
    mockArweavePublisher = MockArweaveVaultPublisher();
    mockSessionCreator = MockSessionCreator();

    publishService = VaultPublishService(
      sessionCreator: mockSessionCreator,
      repository: repo,
      arweavePublisher: mockArweavePublisher,
    );
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    await tempDir.delete(recursive: true);
  });

  test('lança quando a wallet Arweave não está configurada', () async {
    when(() => mockArweavePublisher.publishVaultBlob(any()))
        .thenThrow(Exception('nenhuma wallet Arweave configurada — gere ou importe uma antes de publicar'));

    await expectLater(
      publishService.publish(smartAccountAddress),
      throwsA(isA<Exception>()),
    );
  });

  test('publica no Arweave, publica on-chain e marca a versão como publicada', () async {
    await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');
    final versionBefore = await repo.currentVersion();

    when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
        const ArweavePublishResult(cid: 'ar://TestTxId', contentHash: '0xabc123'));
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async => const SessionCreationResult(
          userOpHash: '0xUserOpHash',
          transactionHash: '0xTxHash',
        ));

    final result = await publishService.publish(smartAccountAddress);

    expect(result.cid, 'ar://TestTxId');
    expect(result.transactionHash, '0xTxHash');

    verify(() => mockSessionCreator.updateVault(
          smartAccountAddress: smartAccountAddress,
          cid: 'ar://TestTxId',
          contentHashHex: '0xabc123',
        )).called(1);

    expect(await repo.pendingChanges(), 0);
    expect(versionBefore, greaterThan(0));
  });

  test('pendingChanges reflete edições feitas depois da última publicação',
      () async {
    when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
        const ArweavePublishResult(cid: 'ar://TestTxId', contentHash: '0xabc123'));
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async => const SessionCreationResult(userOpHash: '0xUserOpHash'));

    await repo.addEntry(site: 'a.com', username: 'u', password: 'p');
    await publishService.publish(smartAccountAddress);
    expect(await repo.pendingChanges(), 0);

    await repo.addEntry(site: 'b.com', username: 'u', password: 'p');
    expect(await repo.pendingChanges(), 1);
  });

  test(
      'pendingChanges volta a 0 depois de favoritar e desfavoritar de volta '
      '(achado da Sessão 136: version bumpa duas vezes mas o conteúdo final '
      'é idêntico ao publicado)', () async {
    when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
        const ArweavePublishResult(cid: 'ar://TestTxId', contentHash: '0xabc123'));
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async => const SessionCreationResult(userOpHash: '0xUserOpHash'));

    final entry = await repo.addEntry(site: 'a.com', username: 'u', password: 'p');
    await publishService.publish(smartAccountAddress);
    expect(await repo.pendingChanges(), 0);

    await repo.setFavorite(entry.id, true);
    expect(await repo.pendingChanges(), 1);
    await repo.setFavorite(entry.id, false);

    expect(await repo.pendingChanges(), 0);
  });

  test(
      'pendingChanges: toggle cancela mesmo com outra pendência real no meio '
      '(achado da Sessão 139: fix da S138 só cancelava se o vault inteiro '
      'voltasse a bater com o publicado — com qualquer outra pendência real '
      'junto, caía no diff de version, que nunca cancela)', () async {
    when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
        const ArweavePublishResult(cid: 'ar://TestTxId', contentHash: '0xabc123'));
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async => const SessionCreationResult(userOpHash: '0xUserOpHash'));

    final entry = await repo.addEntry(site: 'a.com', username: 'u', password: 'p');
    await publishService.publish(smartAccountAddress);
    expect(await repo.pendingChanges(), 0);

    // Pendência real: nova entrada, nunca publicada.
    await repo.addEntry(site: 'b.com', username: 'u2', password: 'p2');
    expect(await repo.pendingChanges(), 1);

    await repo.setFavorite(entry.id, true);
    expect(await repo.pendingChanges(), 2);
    await repo.setFavorite(entry.id, false);

    expect(await repo.pendingChanges(), 1,
        reason: 'toggle deveria cancelar, sobrando só a entrada nova');
  });

  test(
      'edição feita durante a janela de publish (publish+on-chain) continua '
      'pendente depois — não é marcada como publicada por engano (M3, '
      'achado do /code-review high: markPublished tinha TOCTOU relendo o '
      'vault atual do disco em vez de usar o conteúdo que foi de fato '
      'publicado)', () async {
    when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
        const ArweavePublishResult(cid: 'ar://TestTxId', contentHash: '0xabc123'));

    await repo.addEntry(site: 'a.com', username: 'u', password: 'p');

    // Simula a edição concorrente acontecendo enquanto o UserOperation
    // on-chain ainda está em voo — o mock só resolve depois que a nova
    // entrada já foi gravada no repositório real.
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async {
      await repo.addEntry(site: 'concurrent-edit.com', username: 'u2', password: 'p2');
      return const SessionCreationResult(userOpHash: '0xUserOpHash');
    });

    await publishService.publish(smartAccountAddress);

    expect(await repo.pendingChanges(), 1,
        reason: 'a edição concorrente nunca foi publicada on-chain — tem '
            'que continuar pendente, não sumir por causa do markPublished');
  });

  group('Fase 15.7 (documentos publicados separadamente)', () {
    setUp(() {
      when(() => mockSessionCreator.updateVault(
            smartAccountAddress: any(named: 'smartAccountAddress'),
            cid: any(named: 'cid'),
            contentHashHex: any(named: 'contentHashHex'),
          )).thenAnswer((_) async => const SessionCreationResult(userOpHash: '0xUserOpHash'));
    });

    test('publica o conteúdo local de um documento novo e grava cid/contentHash na entrada', () async {
      final entry = await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.document,
        document: const DocumentData(
          name: 'RG', fileName: 'rg.pdf', fileSizeBytes: 5, mimeType: 'application/pdf',
        ),
      );
      await repo.writeDocumentBlob(entry.id, Uint8List.fromList(utf8.encode('conteudo do rg')));

      when(() => mockArweavePublisher.publishDocument(any(), any(), any())).thenAnswer((_) async =>
          const ArweavePublishResult(cid: 'ar://DocTxId', contentHash: '0xdochash'));
      when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
          const ArweavePublishResult(cid: 'ar://VaultTxId', contentHash: '0xvaulthash'));

      await publishService.publish(smartAccountAddress);

      verify(() => mockArweavePublisher.publishDocument(any(), 'rg.pdf', 'application/pdf'))
          .called(1);
      verify(() => mockArweavePublisher.publishVaultBlob(any())).called(1);
      final entries = await repo.listEntries();
      expect(entries.single.document?.cid, 'ar://DocTxId');
      expect(entries.single.document?.contentHash, '0xdochash');
    });

    test('não republica um documento cujo conteúdo local não mudou', () async {
      final entry = await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.document,
        document: const DocumentData(
          name: 'RG', fileName: 'rg.pdf', fileSizeBytes: 5, mimeType: 'application/pdf',
        ),
      );
      final docBlob = await repo.writeDocumentBlob(
          entry.id, Uint8List.fromList(utf8.encode('conteudo do rg')));
      final existingHash = bytesToHex(keccak256(docBlob), include0x: true);
      await repo.setDocumentPinInfo(entry.id, cid: 'ar://AlreadyPublished', contentHash: existingHash);

      when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
          const ArweavePublishResult(cid: 'ar://VaultTxId', contentHash: '0xvaulthash'));

      await publishService.publish(smartAccountAddress);

      // Só publica o blob principal — o documento não mudou desde a última
      // publicação, não deveria ser rechamado (economiza rede/upload).
      verifyNever(() => mockArweavePublisher.publishDocument(any(), any(), any()));
      verify(() => mockArweavePublisher.publishVaultBlob(any())).called(1);
      final entries = await repo.listEntries();
      expect(entries.single.document?.cid, 'ar://AlreadyPublished',
          reason: 'cid antigo deve ser preservado, não sobrescrito');
    });

    test('republica um documento cujo conteúdo local mudou desde a última publicação', () async {
      final entry = await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.document,
        document: const DocumentData(
          name: 'RG', fileName: 'rg.pdf', fileSizeBytes: 5, mimeType: 'application/pdf',
        ),
      );
      await repo.setDocumentPinInfo(entry.id, cid: 'ar://OldTxId', contentHash: '0xoldhash');
      // Conteúdo local mudou depois da última publicação (ex: usuário trocou o arquivo).
      await repo.writeDocumentBlob(entry.id, Uint8List.fromList(utf8.encode('conteudo novo do rg')));

      when(() => mockArweavePublisher.publishDocument(any(), any(), any())).thenAnswer((_) async =>
          const ArweavePublishResult(cid: 'ar://NewTxId', contentHash: '0xnewhash'));
      when(() => mockArweavePublisher.publishVaultBlob(any())).thenAnswer((_) async =>
          const ArweavePublishResult(cid: 'ar://VaultTxId', contentHash: '0xvaulthash'));

      await publishService.publish(smartAccountAddress);

      verify(() => mockArweavePublisher.publishDocument(any(), 'rg.pdf', 'application/pdf')).called(1);
      final entries = await repo.listEntries();
      expect(entries.single.document?.cid, 'ar://NewTxId');
    });
  });
}

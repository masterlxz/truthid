import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/ipfs_pin_client.dart';
import 'package:truthid_mobile/services/pinning_provider_service.dart';
import 'package:truthid_mobile/services/session_creator.dart';
import 'package:truthid_mobile/services/vault_cipher_service.dart';
import 'package:truthid_mobile/services/vault_publish_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockIpfsPinClient extends Mock implements IpfsPinClient {}

class MockPinningProviderService extends Mock implements PinningProviderService {}

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
  late MockIpfsPinClient mockPinClient;
  late MockPinningProviderService mockProviderService;
  late MockSessionCreator mockSessionCreator;
  late VaultPublishService publishService;

  final smartAccountAddress =
      EthereumAddress.fromHex('0xabababababababababababababababababababab');
  const provider = PinningProvider(
    name: 'kubo',
    kind: 'kubo',
    endpointUrl: 'http://localhost:5001',
  );

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
    mockPinClient = MockIpfsPinClient();
    mockProviderService = MockPinningProviderService();
    mockSessionCreator = MockSessionCreator();

    publishService = VaultPublishService(
      sessionCreator: mockSessionCreator,
      repository: repo,
      pinClient: mockPinClient,
      providerService: mockProviderService,
    );
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    await tempDir.delete(recursive: true);
  });

  test('lança quando não há provider de pin configurado', () async {
    when(() => mockProviderService.load()).thenAnswer((_) async => []);

    await expectLater(
      publishService.publish(smartAccountAddress),
      throwsA(isA<Exception>()),
    );
  });

  test('pina, publica on-chain e marca a versão como publicada', () async {
    await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');
    final versionBefore = await repo.currentVersion();

    when(() => mockProviderService.load()).thenAnswer((_) async => [provider]);
    when(() => mockPinClient.pinVault(any(), any())).thenAnswer((_) async => const PinResult(
          cid: 'QmTestCid',
          contentHash: '0xabc123',
          providersOk: ['kubo'],
          providersFailed: [],
        ));
    when(() => mockSessionCreator.updateVault(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          cid: any(named: 'cid'),
          contentHashHex: any(named: 'contentHashHex'),
        )).thenAnswer((_) async => const SessionCreationResult(
          userOpHash: '0xUserOpHash',
          transactionHash: '0xTxHash',
        ));

    final result = await publishService.publish(smartAccountAddress);

    expect(result.cid, 'QmTestCid');
    expect(result.transactionHash, '0xTxHash');

    verify(() => mockSessionCreator.updateVault(
          smartAccountAddress: smartAccountAddress,
          cid: 'QmTestCid',
          contentHashHex: '0xabc123',
        )).called(1);

    expect(await repo.pendingChanges(), 0);
    expect(versionBefore, greaterThan(0));
  });

  test('pendingChanges reflete edições feitas depois da última publicação',
      () async {
    when(() => mockProviderService.load()).thenAnswer((_) async => [provider]);
    when(() => mockPinClient.pinVault(any(), any())).thenAnswer((_) async => const PinResult(
          cid: 'QmTestCid',
          contentHash: '0xabc123',
          providersOk: ['kubo'],
          providersFailed: [],
        ));
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
    when(() => mockProviderService.load()).thenAnswer((_) async => [provider]);
    when(() => mockPinClient.pinVault(any(), any())).thenAnswer((_) async => const PinResult(
          cid: 'QmTestCid',
          contentHash: '0xabc123',
          providersOk: ['kubo'],
          providersFailed: [],
        ));
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
    when(() => mockProviderService.load()).thenAnswer((_) async => [provider]);
    when(() => mockPinClient.pinVault(any(), any())).thenAnswer((_) async => const PinResult(
          cid: 'QmTestCid',
          contentHash: '0xabc123',
          providersOk: ['kubo'],
          providersFailed: [],
        ));
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
}

import 'dart:io';
import 'dart:typed_data';

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

  setUpAll(() {
    registerFallbackValue(smartAccountAddress);
  });

  setUp(() async {
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
}

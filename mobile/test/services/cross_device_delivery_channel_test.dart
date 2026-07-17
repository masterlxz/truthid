import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/services/cross_device_delivery_channel.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/ipfs_pin_client.dart';
import 'package:truthid_mobile/services/pinning_provider_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';
import 'package:truthid_mobile/services/result_delivery_channel.dart';

class MockEciesService extends Mock implements EciesService {}

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockIpfsPinClient extends Mock implements IpfsPinClient {}

class MockPinningProviderService extends Mock
    implements PinningProviderService {}

void main() {
  late MockEciesService mockEcies;
  late MockRemoteSignerLanServer mockLanServer;
  late MockIpfsPinClient mockIpfsPinClient;
  late MockPinningProviderService mockPinningProviderService;

  final requesterPubKeyHex = '0x02${'ab' * 32}';
  final expiresAt = DateTime.now().add(const Duration(minutes: 3));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DateTime.now());
    registerFallbackValue(<PinningProvider>[]);
  });

  setUp(() {
    mockEcies = MockEciesService();
    mockLanServer = MockRemoteSignerLanServer();
    mockIpfsPinClient = MockIpfsPinClient();
    mockPinningProviderService = MockPinningProviderService();

    when(() => mockEcies.encrypt(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(() => mockPinningProviderService.load()).thenAnswer((_) async => []);
    when(() => mockIpfsPinClient.publishDeadDrop(any(), any(), any()))
        .thenAnswer((_) async => null);
  });

  CrossDeviceDeliveryChannel buildChannel() => CrossDeviceDeliveryChannel(
        requesterPubKeyHex: requesterPubKeyHex,
        ecies: mockEcies,
        lanServer: mockLanServer,
        ipfsPinClient: mockIpfsPinClient,
        pinningProviderService: mockPinningProviderService,
      );

  test('cifra o result, serve via LAN, e devolve sent quando serveOnce=true',
      () async {
    when(() => mockLanServer.serveOnce(
          encryptedBlob: any(named: 'encryptedBlob'),
          sessionId: any(named: 'sessionId'),
          expiresAt: any(named: 'expiresAt'),
        )).thenAnswer((_) async => true);

    final channel = buildChannel();
    final result = await channel.deliver(
      result: const {'status': 'signed'},
      sessionId: 'session-1',
      expiresAt: expiresAt,
    );

    verify(() => mockEcies.encrypt(any(), requesterPubKeyHex)).called(1);
    expect(result.outcome, DeliveryOutcome.sent);
  });

  test('serveOnce=false devolve timeout, não erro', () async {
    when(() => mockLanServer.serveOnce(
          encryptedBlob: any(named: 'encryptedBlob'),
          sessionId: any(named: 'sessionId'),
          expiresAt: any(named: 'expiresAt'),
        )).thenAnswer((_) async => false);

    final channel = buildChannel();
    final result = await channel.deliver(
      result: const {'status': 'rejected'},
      sessionId: 'session-2',
      expiresAt: expiresAt,
    );

    expect(result.outcome, DeliveryOutcome.timeout);
  });

  test('dead-drop com sucesso preenche deadDropIpnsName', () async {
    when(() => mockPinningProviderService.load()).thenAnswer(
      (_) async => const [
        PinningProvider(
          name: 'local-kubo',
          kind: 'kubo',
          endpointUrl: 'http://127.0.0.1:5001',
        ),
      ],
    );
    when(() => mockIpfsPinClient.publishDeadDrop(any(), any(), any()))
        .thenAnswer((_) async => 'k51abc');
    when(() => mockLanServer.serveOnce(
          encryptedBlob: any(named: 'encryptedBlob'),
          sessionId: any(named: 'sessionId'),
          expiresAt: any(named: 'expiresAt'),
        )).thenAnswer((_) async => true);

    final channel = buildChannel();
    final result = await channel.deliver(
      result: const {'status': 'signed'},
      sessionId: 'session-3',
      expiresAt: expiresAt,
    );

    expect(result.deadDropIpnsName, 'k51abc');
    expect(result.deadDropError, isNull);
  });

  test('erro no dead-drop não derruba o LAN nem lança — vira deadDropError',
      () async {
    when(() => mockPinningProviderService.load())
        .thenThrow(Exception('boom'));
    when(() => mockLanServer.serveOnce(
          encryptedBlob: any(named: 'encryptedBlob'),
          sessionId: any(named: 'sessionId'),
          expiresAt: any(named: 'expiresAt'),
        )).thenAnswer((_) async => true);

    final channel = buildChannel();
    final result = await channel.deliver(
      result: const {'status': 'signed'},
      sessionId: 'session-4',
      expiresAt: expiresAt,
    );

    expect(result.outcome, DeliveryOutcome.sent);
    expect(result.deadDropError, contains('boom'));
  });
}

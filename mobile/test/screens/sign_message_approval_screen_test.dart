import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/sign_message_approval_screen.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/ipfs_pin_client.dart';
import 'package:truthid_mobile/services/pinning_provider_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockEciesService extends Mock implements EciesService {}

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockIpfsPinClient extends Mock implements IpfsPinClient {}

class MockPinningProviderService extends Mock
    implements PinningProviderService {}

void main() {
  late MockDeviceKeyService mockKeyService;
  late MockEciesService mockEcies;
  late MockRemoteSignerLanServer mockLanServer;
  late MockIpfsPinClient mockIpfsPinClient;
  late MockPinningProviderService mockPinningProviderService;

  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey = '0x02${'ab' * 32}';

  Map<String, dynamic> validPayload({
    String sessionId = 'session-abc',
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
    String appName = 'Practice Valuation',
    String? purpose = 'vault-sync-key',
  }) =>
      {
        'action': 'truthid-sign-message',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
        'appName': appName,
        'purpose': purpose,
      };

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DateTime.now());
    registerFallbackValue(<PinningProvider>[]);
  });

  setUp(() {
    mockKeyService = MockDeviceKeyService();
    mockEcies = MockEciesService();
    mockLanServer = MockRemoteSignerLanServer();
    mockIpfsPinClient = MockIpfsPinClient();
    mockPinningProviderService = MockPinningProviderService();

    when(() => mockEcies.encrypt(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    // Sem provider Kubo configurado por padrão — mimetiza o early-return
    // silencioso do IpfsPinClient.publishDeadDrop real (mesmo padrão do
    // vault_session_screen_test.dart, que nem mocka IpfsPinClient por causa
    // disso). Aqui ele é mockado porque os testes de dead-drop abaixo
    // precisam verificar a chamada; testes específicos sobrescrevem o stub.
    when(() => mockPinningProviderService.load()).thenAnswer((_) async => []);
    when(() => mockIpfsPinClient.publishDeadDrop(any(), any(), any()))
        .thenAnswer((_) async => null);
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: SignMessageApprovalScreen(
        payload: payload,
        deviceKeyService: mockKeyService,
        eciesService: mockEcies,
        lanServer: mockLanServer,
        ipfsPinClient: mockIpfsPinClient,
        pinningProviderService: mockPinningProviderService,
      ),
    );
  }

  group('validação do schema v1 do QR', () {
    testWidgets('payload sem sessionId mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(sessionId: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload sem ephemeralPubKey mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(ephemeralPubKey: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('schema version desconhecida mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(v: 2)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('QR expirado mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(
        validPayload(
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('appName vazio mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(appName: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('purpose com caractere inválido mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(purpose: 'has space')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('purpose vazio mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(purpose: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload válido mostra a mensagem exata a ser assinada',
        (tester) async {
      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();
      expect(
        find.text('TruthID Message Signing: Practice Valuation:vault-sync-key'),
        findsOneWidget,
      );
    });
  });

  group('Approve', () {
    testWidgets('assina a mensagem exata, cifra e serve — mostra "Sent"',
        (tester) async {
      when(() => mockKeyService.signChallenge(any()))
          .thenAnswer((_) async => '0xdeadbeef');
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockKeyService.signChallenge(
            'TruthID Message Signing: Practice Valuation:vault-sync-key',
          )).called(1);
      verify(() => mockEcies.encrypt(any(), validEphemeralPubKey)).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('timeout: ninguém conectou, mostra "Nothing arrived"',
        (tester) async {
      when(() => mockKeyService.signChallenge(any()))
          .thenAnswer((_) async => '0xdeadbeef');
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => false);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing arrived'), findsOneWidget);
    });
  });

  group('Dead-drop (IPFS/IPNS)', () {
    testWidgets(
        'com provider Kubo configurado, publica em paralelo com o LAN e '
        'mostra "Dead-drop backup published"', (tester) async {
      final providers = [
        const PinningProvider(
          name: 'local-kubo',
          kind: 'kubo',
          endpointUrl: 'http://127.0.0.1:5001',
        ),
      ];
      when(() => mockPinningProviderService.load())
          .thenAnswer((_) async => providers);
      when(() => mockIpfsPinClient.publishDeadDrop(any(), any(), any()))
          .thenAnswer((_) async => 'k51abc');
      when(() => mockKeyService.signChallenge(any()))
          .thenAnswer((_) async => '0xdeadbeef');
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() =>
              mockIpfsPinClient.publishDeadDrop('session-abc', any(), providers))
          .called(1);
      expect(find.text('Dead-drop backup published (IPFS/IPNS).'),
          findsOneWidget);
    });

    testWidgets(
        'erro no dead-drop não impede o envio via LAN, mostra "unavailable"',
        (tester) async {
      when(() => mockPinningProviderService.load())
          .thenThrow(Exception('boom'));
      when(() => mockKeyService.signChallenge(any()))
          .thenAnswer((_) async => '0xdeadbeef');
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Dead-drop backup unavailable this time.'),
          findsOneWidget);
    });

  });

  group('Reject', () {
    testWidgets('nunca chama signChallenge, serve {status: rejected}',
        (tester) async {
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verifyNever(() => mockKeyService.signChallenge(any()));
      verify(() => mockEcies.encrypt(any(), validEphemeralPubKey)).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });
  });
}

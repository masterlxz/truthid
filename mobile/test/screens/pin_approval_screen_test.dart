import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/pin_approval_screen.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/ipfs_pin_client.dart';
import 'package:truthid_mobile/services/pin_content_cipher_service.dart';
import 'package:truthid_mobile/services/pinning_provider_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';
import 'package:truthid_mobile/services/result_delivery_channel.dart';

class MockEciesService extends Mock implements EciesService {}

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockIpfsPinClient extends Mock implements IpfsPinClient {}

class MockPinningProviderService extends Mock
    implements PinningProviderService {}

class MockResultDeliveryChannel extends Mock
    implements ResultDeliveryChannel {}

void main() {
  late MockEciesService mockEcies;
  late MockRemoteSignerLanServer mockLanServer;
  late MockIpfsPinClient mockIpfsPinClient;
  late MockPinningProviderService mockPinningProviderService;
  late MockResultDeliveryChannel mockDelivery;

  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey = '0x02${'ab' * 32}';
  // sessionId de teste, formato do QR real (hex, 16 bytes) — derivePinContentKey
  // faz hexToBytes sobre isso, diferente do sessionId opaco usado nos testes
  // irmãos de sign-message (que nunca decodifica o sessionId como hex).
  const testSessionId = '000102030405060708090a0b0c0d0e0f';

  Map<String, dynamic> validPayload({
    String sessionId = testSessionId,
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
    String appName = 'Practice Valuation',
  }) =>
      {
        'action': 'truthid-pin',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
        'appName': appName,
      };

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DateTime.now());
    registerFallbackValue(<PinningProvider>[]);
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockEcies = MockEciesService();
    mockLanServer = MockRemoteSignerLanServer();
    mockIpfsPinClient = MockIpfsPinClient();
    mockPinningProviderService = MockPinningProviderService();
    mockDelivery = MockResultDeliveryChannel();
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: PinApprovalScreen(
        payload: payload,
        eciesService: mockEcies,
        lanServer: mockLanServer,
        ipfsPinClient: mockIpfsPinClient,
        pinningProviderService: mockPinningProviderService,
        deliveryChannel: mockDelivery,
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

    testWidgets('payload válido começa recebendo o conteúdo (fase 1)',
        (tester) async {
      // Completer que nunca resolve — diferente de Future.delayed, não cria
      // nenhum Timer real, então não dispara o "Timer is still pending"
      // do binding de teste ao encerrar com um único pump() (sem settle).
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) => Completer<Uint8List?>().future);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pump();
      expect(find.textContaining('wants to send content to pin'),
          findsOneWidget);
    });
  });

  group('fase 1 — recebimento do conteúdo', () {
    testWidgets('timeout na fase 1 mostra "Nothing arrived"', (tester) async {
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => null);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing arrived'), findsOneWidget);
    });

    testWidgets('conteúdo recebido e decifrado mostra a tela de aprovação',
        (tester) async {
      final key = derivePinContentKey(testSessionId);
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encrypted = await encryptPinContent(plaintext, key);

      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(
        find.text('Practice Valuation wants to pin content to your IPFS '
            'providers'),
        findsOneWidget,
      );
      expect(find.text('Size: 5 bytes'), findsOneWidget);
    });

    testWidgets('conteúdo cifrado com sessionId errado mostra erro',
        (tester) async {
      final wrongKey = derivePinContentKey('deadbeef');
      final encrypted = await encryptPinContent(
        Uint8List.fromList([1, 2, 3]),
        wrongKey,
      );

      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to decrypt'), findsOneWidget);
    });
  });

  group('fase 2 — Approve', () {
    Future<void> pumpToApproval(WidgetTester tester) async {
      final key = derivePinContentKey(testSessionId);
      final encrypted =
          await encryptPinContent(Uint8List.fromList([1, 2, 3]), key);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();
    }

    testWidgets('pina via providers configurados e entrega {status: pinned}',
        (tester) async {
      final providers = [
        const PinningProvider(
          name: 'local-kubo',
          kind: 'kubo',
          endpointUrl: 'http://127.0.0.1:5001',
        ),
      ];
      when(() => mockPinningProviderService.load())
          .thenAnswer((_) async => providers);
      when(() => mockIpfsPinClient.pinVault(any(), providers)).thenAnswer(
        (_) async => const PinResult(
          cid: 'bafy123',
          contentHash: '0xhash',
          providersOk: ['local-kubo'],
          providersFailed: [],
        ),
      );
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {
              'status': 'pinned',
              'cid': 'bafy123',
              'contentHash': '0xhash',
              'providersOk': ['local-kubo'],
              'providersFailed': <String>[],
            },
            sessionId: testSessionId,
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('sem provider configurado entrega {status: failed}',
        (tester) async {
      when(() => mockPinningProviderService.load()).thenAnswer((_) async => []);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: any(
              named: 'result',
              that: containsPair('status', 'failed'),
            ),
            sessionId: testSessionId,
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      verifyNever(() => mockIpfsPinClient.pinVault(any(), any()));
    });
  });

  group('fase 2 — Reject', () {
    testWidgets('nunca chama pinVault, entrega {status: rejected}',
        (tester) async {
      final key = derivePinContentKey(testSessionId);
      final encrypted =
          await encryptPinContent(Uint8List.fromList([1, 2, 3]), key);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verifyNever(() => mockIpfsPinClient.pinVault(any(), any()));
      verify(() => mockDelivery.deliver(
            result: {'status': 'rejected'},
            sessionId: testSessionId,
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });
  });
}

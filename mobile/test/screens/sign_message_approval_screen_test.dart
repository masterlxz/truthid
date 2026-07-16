import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/sign_message_approval_screen.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockEciesService extends Mock implements EciesService {}

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

void main() {
  late MockDeviceKeyService mockKeyService;
  late MockEciesService mockEcies;
  late MockRemoteSignerLanServer mockLanServer;

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
  });

  setUp(() {
    mockKeyService = MockDeviceKeyService();
    mockEcies = MockEciesService();
    mockLanServer = MockRemoteSignerLanServer();

    when(() => mockEcies.encrypt(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: SignMessageApprovalScreen(
        payload: payload,
        deviceKeyService: mockKeyService,
        eciesService: mockEcies,
        lanServer: mockLanServer,
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

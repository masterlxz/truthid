import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/screens/approval_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/session_creator.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockBlockchainService extends Mock implements BlockchainService {}

class MockSessionCreator extends Mock implements SessionCreator {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

void main() {
  late MockDeviceKeyService mockKeyService;
  late MockBlockchainService mockBlockchainService;
  late MockSessionCreator mockSessionCreator;
  late MockLocalStorageService mockLocalStorageService;
  late List<Map<String, dynamic>> capturedResponses;

  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'));
  });

  setUp(() {
    mockKeyService = MockDeviceKeyService();
    mockBlockchainService = MockBlockchainService();
    mockSessionCreator = MockSessionCreator();
    mockLocalStorageService = MockLocalStorageService();
    capturedResponses = [];

    when(() => mockKeyService.signChallenge(any()))
        .thenAnswer((_) async => '0xabc123sig');
    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => '0x1234567890123456789012345678901234567890');
    when(() => mockKeyService.signHash(any()))
        .thenAnswer((_) async => '0xsessionSig');

    // Cenário padrão: device já pareado com uma identidade que existe on-chain.
    when(() => mockLocalStorageService.getPairedIdentityId())
        .thenAnswer((_) async => '1');
    when(() => mockLocalStorageService.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockBlockchainService.getIdentityByUsername('alice'))
        .thenAnswer((_) async => IdentityInfo(
              id: BigInt.one,
              controller: smartAccountAddress,
            ));
    when(() => mockSessionCreator.createSession(
          identityId: any(named: 'identityId'),
          smartAccountAddress: any(named: 'smartAccountAddress'),
          sessionHash: any(named: 'sessionHash'),
          devicePubKey: any(named: 'devicePubKey'),
          sessionSignatureHex: any(named: 'sessionSignatureHex'),
        )).thenAnswer((_) async => const SessionCreationResult(
          userOpHash: '0xUserOpHashXYZ',
          transactionHash: '0xTxHash',
        ));
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: ApprovalScreen(
        payload: payload,
        keyService: mockKeyService,
        blockchainService: mockBlockchainService,
        sessionCreator: mockSessionCreator,
        localStorageService: mockLocalStorageService,
        postResponse: (r) async => capturedResponses.add(r),
      ),
    );
  }

  final validPayload = {
    'challenge': {
      'nonce': 'test-nonce-123',
      'origin': 'example.com',
      'issuedAt': DateTime(2026, 6, 28, 12).millisecondsSinceEpoch,
    },
    'callbackUrl': 'https://example.com/auth/verify',
  };

  group('error states', () {
    testWidgets('shows error when challenge is missing', (tester) async {
      await tester.pumpWidget(buildScreen({'callbackUrl': 'https://example.com/auth/verify'}));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('shows error when callbackUrl is missing', (tester) async {
      await tester.pumpWidget(buildScreen({
        'challenge': {'nonce': 'n', 'origin': 'x', 'issuedAt': 0},
      }));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error when callbackUrl is http (not https)', (tester) async {
      await tester.pumpWidget(buildScreen({
        'challenge': {'nonce': 'n', 'origin': 'x', 'issuedAt': 0},
        'callbackUrl': 'http://example.com/auth/verify',
      }));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('https'), findsOneWidget);
    });
  });

  group('challenge UI', () {
    testWidgets('shows site name, Approve and Reject buttons for valid payload',
        (tester) async {
      await tester.pumpWidget(buildScreen(validPayload));

      expect(find.text('Login request received'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });
  });

  group('approve flow', () {
    testWidgets(
        'signs the challenge, creates the session on-chain and posts an approved response',
        (tester) async {
      await tester.pumpWidget(buildScreen(validPayload));
      await tester.pump(); // resolve LocalStorageService futures (identity pareada)

      await tester.tap(find.text('Approve'));
      // pumpAndSettle resolve os futures de mock (microtasks) e renderiza "done"
      await tester.pumpAndSettle();

      expect(capturedResponses, hasLength(1));
      expect(capturedResponses[0]['approved'], isTrue);
      expect(capturedResponses[0]['nonce'], 'test-nonce-123');
      expect(capturedResponses[0]['signature'], isNotNull);
      expect(capturedResponses[0]['deviceAddress'], isNotNull);
      expect(capturedResponses[0]['sessionSignature'], isNotNull);

      verify(() => mockKeyService.signChallenge(any())).called(1);
      verify(() => mockKeyService.getDeviceAddress()).called(1);
      verify(() => mockKeyService.signHash(any())).called(1);
      verify(() => mockBlockchainService.getIdentityByUsername('alice'))
          .called(1);
      verify(() => mockSessionCreator.createSession(
            identityId: BigInt.one,
            smartAccountAddress: smartAccountAddress,
            sessionHash: any(named: 'sessionHash'),
            devicePubKey: EthereumAddress.fromHex(
                '0x1234567890123456789012345678901234567890'),
            sessionSignatureHex: '0xsessionSig',
          )).called(1);

      // Avança além dos 800ms do Future.delayed para que o timer não fique
      // pendente quando o framework desmontar a árvore de widgets.
      await tester.pump(const Duration(milliseconds: 1000));
    });

    testWidgets(
        'shows an error and never posts if the device is not paired with any identity',
        (tester) async {
      when(() => mockLocalStorageService.getPairedUsername())
          .thenAnswer((_) async => null);

      await tester.pumpWidget(buildScreen(validPayload));
      await tester.pump();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(capturedResponses, isEmpty);
      verifyNever(() => mockSessionCreator.createSession(
            identityId: any(named: 'identityId'),
            smartAccountAddress: any(named: 'smartAccountAddress'),
            sessionHash: any(named: 'sessionHash'),
            devicePubKey: any(named: 'devicePubKey'),
            sessionSignatureHex: any(named: 'sessionSignatureHex'),
          ));
    });

    testWidgets(
        'shows an error and never posts if the identity cannot be resolved on-chain',
        (tester) async {
      when(() => mockBlockchainService.getIdentityByUsername('alice'))
          .thenAnswer((_) async => null);

      await tester.pumpWidget(buildScreen(validPayload));
      await tester.pump();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(capturedResponses, isEmpty);
      verifyNever(() => mockSessionCreator.createSession(
            identityId: any(named: 'identityId'),
            smartAccountAddress: any(named: 'smartAccountAddress'),
            sessionHash: any(named: 'sessionHash'),
            devicePubKey: any(named: 'devicePubKey'),
            sessionSignatureHex: any(named: 'sessionSignatureHex'),
          ));
    });

    testWidgets(
        'shows an error and never notifies the website if on-chain session creation fails',
        (tester) async {
      when(() => mockSessionCreator.createSession(
            identityId: any(named: 'identityId'),
            smartAccountAddress: any(named: 'smartAccountAddress'),
            sessionHash: any(named: 'sessionHash'),
            devicePubKey: any(named: 'devicePubKey'),
            sessionSignatureHex: any(named: 'sessionSignatureHex'),
          )).thenThrow(Exception('insufficient funds for gas'));

      await tester.pumpWidget(buildScreen(validPayload));
      await tester.pump();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('enough ETH'), findsOneWidget);
      expect(capturedResponses, isEmpty);
    });
  });

  group('reject flow', () {
    testWidgets('posts a rejection without signing', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload));

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(capturedResponses, hasLength(1));
      expect(capturedResponses[0]['approved'], isFalse);
      expect(capturedResponses[0]['nonce'], 'test-nonce-123');

      verifyNever(() => mockKeyService.signChallenge(any()));
      verifyNever(() => mockKeyService.signHash(any()));

      // Flush do timer de 800ms
      await tester.pump(const Duration(milliseconds: 1000));
    });

    testWidgets('prevents a second response after the first was sent', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload));

      // tap(Approve) executa _approve() de forma síncrona até o primeiro await,
      // setando _responded = true antes de qualquer pump.
      await tester.tap(find.text('Approve'));
      // tap(Reject) chega enquanto o challenge ainda está na tela (sem pump).
      // _reject() vê _responded == true e retorna sem postar nada.
      await tester.tap(find.text('Reject'));

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1000)); // flush timer

      expect(capturedResponses, hasLength(1));
    });
  });
}

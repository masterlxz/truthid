import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/screens/sign_request_approval_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/bundler_config_service.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';
import 'package:truthid_mobile/services/session_creator.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockBundlerConfigService extends Mock implements BundlerConfigService {}

class MockEciesService extends Mock implements EciesService {}

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockSessionCreator extends Mock implements SessionCreator {}

// keccak256("transfer(address,uint256)")[0:4] — mesma técnica que a tela usa
// pra verificar o seletor declarado contra o callData recebido.
final _transferSelector = bytesToHex(
  keccak256(Uint8List.fromList('transfer(address,uint256)'.codeUnits))
      .sublist(0, 4),
  include0x: true,
);

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockBundlerConfigService mockBundlerConfig;
  late MockEciesService mockEcies;
  late MockRemoteSignerLanServer mockLanServer;
  late MockSessionCreator mockSessionCreator;

  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey = '0x02${'ab' * 32}';
  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');
  final destAddress = EthereumAddress.fromHex(
      '0xcccccccccccccccccccccccccccccccccccccccc');

  Map<String, dynamic> validPayload({
    String sessionId = 'session-abc',
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
    String appName = 'Practice Valuation',
    String? dest,
    String? value = '1000',
    String? callData,
    String? functionSignature = 'transfer(address,uint256)',
  }) =>
      {
        'action': 'truthid-sign-request',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
        'appName': appName,
        'dest': dest ?? destAddress.hexEip55,
        'value': value,
        'callData': callData ?? '$_transferSelector${'ab' * 64}',
        'functionSignature': functionSignature,
      };

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(smartAccountAddress);
    registerFallbackValue(destAddress);
    registerFallbackValue(BigInt.zero);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockBundlerConfig = MockBundlerConfigService();
    mockEcies = MockEciesService();
    mockLanServer = MockRemoteSignerLanServer();
    mockSessionCreator = MockSessionCreator();

    when(() => mockStorage.getPairedIdentityId())
        .thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer(
      (_) async =>
          IdentityInfo(id: BigInt.one, controller: smartAccountAddress),
    );
    when(() => mockEcies.encrypt(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: SignRequestApprovalScreen(
        payload: payload,
        sessionCreator: mockSessionCreator,
        blockchainService: mockBlockchain,
        localStorageService: mockStorage,
        bundlerConfigService: mockBundlerConfig,
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

    testWidgets('dest ausente mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(dest: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('callData ausente mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(callData: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('functionSignature ausente mostra erro', (tester) async {
      await tester
          .pumpWidget(buildScreen(validPayload(functionSignature: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });
  });

  group('resolução da smart account', () {
    testWidgets('não pareado mostra erro, nunca chama BlockchainService',
        (tester) async {
      when(() => mockStorage.getPairedIdentityId())
          .thenAnswer((_) async => null);
      when(() => mockStorage.getPairedUsername())
          .thenAnswer((_) async => null);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.textContaining("isn't paired"), findsOneWidget);
      verifyNever(() => mockBlockchain.getIdentityByUsername(any()));
    });

    testWidgets('pareado mostra a tela pendente com os dados da requisição',
        (tester) async {
      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(
        find.text('Practice Valuation wants to execute a transaction'),
        findsOneWidget,
      );
      expect(find.textContaining('Function (verified)'), findsOneWidget);
    });

    testWidgets('functionSignature que não bate o seletor mostra unverified',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        validPayload(functionSignature: 'approve(address,uint256)'),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Function (unverified)'), findsOneWidget);
    });
  });

  group('Approve', () {
    testWidgets(
        'executa a UserOp, entrega o resultado e mostra "Sent" com o userOpHash',
        (tester) async {
      when(() => mockSessionCreator.executeArbitraryCall(
            smartAccountAddress: any(named: 'smartAccountAddress'),
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            innerCallData: any(named: 'innerCallData'),
          )).thenAnswer((_) async => const SessionCreationResult(
            userOpHash: '0xUserOpHashXYZ',
            transactionHash: '0xTxHash',
          ));
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockSessionCreator.executeArbitraryCall(
            smartAccountAddress: smartAccountAddress,
            dest: destAddress,
            value: BigInt.from(1000),
            innerCallData: hexToBytes('$_transferSelector${'ab' * 64}'),
          )).called(1);
      verify(() => mockEcies.encrypt(any(), validEphemeralPubKey)).called(1);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.textContaining('0xUserOpHashXYZ'), findsOneWidget);
    });

    testWidgets(
        'falha na execução ainda assim entrega {status: failed} e mostra em "Sent"',
        (tester) async {
      when(() => mockSessionCreator.executeArbitraryCall(
            smartAccountAddress: any(named: 'smartAccountAddress'),
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            innerCallData: any(named: 'innerCallData'),
          )).thenThrow(Exception('bundler rejected the UserOperation'));
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
      expect(find.textContaining('Transaction failed'), findsOneWidget);
    });

    testWidgets('timeout: ninguém conectou, mostra "Nothing arrived"',
        (tester) async {
      when(() => mockSessionCreator.executeArbitraryCall(
            smartAccountAddress: any(named: 'smartAccountAddress'),
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            innerCallData: any(named: 'innerCallData'),
          )).thenAnswer((_) async => const SessionCreationResult(
            userOpHash: '0xUserOpHashXYZ',
          ));
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
    testWidgets('nunca chama executeArbitraryCall, serve {status: rejected}',
        (tester) async {
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      // A tela pendente tem mais conteúdo que a de sign-message (3 InfoRow +
      // callData cru), então o Reject pode ficar fora do viewport de teste
      // (800x600) sem rolar até ele primeiro.
      await tester.ensureVisible(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verifyNever(() => mockSessionCreator.executeArbitraryCall(
            smartAccountAddress: any(named: 'smartAccountAddress'),
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            innerCallData: any(named: 'innerCallData'),
          ));
      verify(() => mockEcies.encrypt(any(), validEphemeralPubKey)).called(1);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.textContaining('You rejected this request'),
          findsOneWidget);
    });
  });
}

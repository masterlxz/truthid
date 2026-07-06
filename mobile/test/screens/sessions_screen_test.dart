import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/screens/sessions_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/bundler_config_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/session_creator.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockBundlerConfigService extends Mock implements BundlerConfigService {}

class MockSessionCreator extends Mock implements SessionCreator {}

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockDeviceKeyService mockKeyService;
  late MockBundlerConfigService mockBundlerConfigService;
  late MockSessionCreator mockSessionCreator;

  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');
  final deviceAddress = '0x1234567890123456789012345678901234567890';
  final activeSessionHash =
      keccak256(Uint8List.fromList('active-session'.codeUnits));
  final revokedSessionHash =
      keccak256(Uint8List.fromList('revoked-session'.codeUnits));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(smartAccountAddress);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockKeyService = MockDeviceKeyService();
    mockBundlerConfigService = MockBundlerConfigService();
    mockSessionCreator = MockSessionCreator();

    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => deviceAddress);
    when(() => mockStorage.getPairedIdentityId())
        .thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async => DeviceInfo(
        identityId: BigInt.one,
        revoked: false,
        exists: true,
      ),
    );
    when(() => mockBlockchain.getSessionsForIdentity(BigInt.one)).thenAnswer(
      (_) async => [
        SessionInfo(
          hash: activeSessionHash,
          devicePubKey: '0x9999999999999999999999999999999999999999',
          createdAt: DateTime(2026, 1, 1),
          isRevoked: false,
        ),
        SessionInfo(
          hash: revokedSessionHash,
          devicePubKey: '0x9999999999999999999999999999999999999999',
          createdAt: DateTime(2026, 1, 2),
          isRevoked: true,
        ),
      ],
    );
    when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer(
      (_) async => IdentityInfo(id: BigInt.one, controller: smartAccountAddress),
    );
  });

  Widget buildScreen() {
    return MaterialApp(
      // Na app real, SessionsScreen vive dentro do Scaffold/IndexedStack de
      // RootScreen (main.dart) — o Scaffold aqui reproduz isso pra que
      // ScaffoldMessenger.of(context) (usado pelo snackbar de erro) funcione.
      home: Scaffold(
        body: SessionsScreen(
          blockchainService: mockBlockchain,
          localStorageService: mockStorage,
          deviceKeyService: mockKeyService,
          bundlerConfigService: mockBundlerConfigService,
          sessionCreator: mockSessionCreator,
        ),
      ),
    );
  }

  testWidgets(
      'mostra botão de revogar só para sessões ativas, não para já revogadas',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);
  });

  testWidgets(
      'confirmar o diálogo chama SessionCreator.revokeSession e recarrega a lista',
      (tester) async {
    when(() => mockSessionCreator.revokeSession(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          sessionHash: any(named: 'sessionHash'),
        )).thenAnswer((_) async => const SessionCreationResult(
          userOpHash: '0xUserOpHashXYZ',
          transactionHash: '0xTxHash',
        ));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Revoke session?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();

    verify(() => mockSessionCreator.revokeSession(
          smartAccountAddress: smartAccountAddress,
          sessionHash: activeSessionHash,
        )).called(1);
    // getSessionsForIdentity é chamado uma vez no load inicial e outra no
    // reload pós-revogação.
    verify(() => mockBlockchain.getSessionsForIdentity(BigInt.one)).called(2);
  });

  testWidgets('cancelar o diálogo não chama revokeSession', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockSessionCreator.revokeSession(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          sessionHash: any(named: 'sessionHash'),
        ));
  });

  testWidgets(
      'mostra um snackbar de erro se revokeSession falhar, sem travar a tela',
      (tester) async {
    when(() => mockSessionCreator.revokeSession(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          sessionHash: any(named: 'sessionHash'),
        )).thenThrow(Exception('bundler rejected the UserOperation'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not revoke the session. Make sure your account has enough ETH for gas.',
      ),
      findsOneWidget,
    );
  });
}

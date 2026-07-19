import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/models/smart_account_activity.dart';
import 'package:truthid_mobile/screens/wallet_screen.dart';
import 'package:truthid_mobile/services/activity_cache_service.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/bundler_config_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/session_creator.dart';
import 'package:truthid_mobile/services/smart_account_activity_scanner.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockBundlerConfigService extends Mock implements BundlerConfigService {}

class MockSessionCreator extends Mock implements SessionCreator {}

class MockSmartAccountActivityScanner extends Mock
    implements SmartAccountActivityScanner {}

class MockActivityCacheService extends Mock implements ActivityCacheService {}

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockDeviceKeyService mockKeyService;
  late MockBundlerConfigService mockBundlerConfigService;
  late MockSessionCreator mockSessionCreator;
  late MockSmartAccountActivityScanner mockActivityScanner;
  late MockActivityCacheService mockActivityCacheService;

  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');
  final deviceAddress = '0x1234567890123456789012345678901234567890';

  setUpAll(() {
    registerFallbackValue(smartAccountAddress);
    registerFallbackValue(BigInt.one);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockKeyService = MockDeviceKeyService();
    mockBundlerConfigService = MockBundlerConfigService();
    mockSessionCreator = MockSessionCreator();
    mockActivityScanner = MockSmartAccountActivityScanner();
    mockActivityCacheService = MockActivityCacheService();

    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => deviceAddress);
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => 'alice');
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async => DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );
    when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer(
      (_) async => IdentityInfo(id: BigInt.one, controller: smartAccountAddress),
    );
    when(() => mockBlockchain.getBalance(smartAccountAddress))
        .thenAnswer((_) async => BigInt.from(123000000000000000)); // 0.123 ETH
    // Precisa ser maior que os deploy blocks reais (~48.2M na Base Mainnet)
    // pra que `_loadActivity` não pule o scan achando que "já passou do tip"
    // (fromBlock > latest) — esse guard existe pra evitar chamar o scanner
    // com uma faixa invertida quando a chain ainda não chegou no deploy block.
    when(() => mockBlockchain.getLatestBlockNumber())
        .thenAnswer((_) async => 48300000);

    when(() => mockActivityCacheService.read(BigInt.one))
        .thenAnswer((_) async => null);
    when(() => mockActivityCacheService.write(
          any(),
          lastScannedBlock: any(named: 'lastScannedBlock'),
          activities: any(named: 'activities'),
        )).thenAnswer((_) async {});
    when(() => mockActivityCacheService.clear(any())).thenAnswer((_) async {});

    when(() => mockActivityScanner.scan(
          identityId: any(named: 'identityId'),
          fromBlock: any(named: 'fromBlock'),
          toBlock: any(named: 'toBlock'),
          onChunkScanned: any(named: 'onChunkScanned'),
        )).thenAnswer((_) async => []);
  });

  Widget buildScreen() {
    return MaterialApp(
      home: Scaffold(
        body: WalletScreen(
          blockchainService: mockBlockchain,
          localStorageService: mockStorage,
          deviceKeyService: mockKeyService,
          bundlerConfigService: mockBundlerConfigService,
          sessionCreator: mockSessionCreator,
          activityScanner: mockActivityScanner,
          activityCacheService: mockActivityCacheService,
        ),
      ),
    );
  }

  testWidgets('mostra o saldo da smart account resolvido on-chain',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('0.1230 ETH'), findsOneWidget);
  });

  testWidgets('mostra o resumo de custo por tipo a partir do cache',
      (tester) async {
    when(() => mockActivityCacheService.read(BigInt.one)).thenAnswer(
      (_) async => CachedActivity(
        lastScannedBlock: 900,
        activities: [
          SmartAccountActivity(
            type: SmartAccountActivityType.sessionCreated,
            hash: '0x${'a1' * 32}', // 66 chars, mesmo formato de um tx hash real
            blockNumber: 100,
            logIndex: 0,
            timestamp: 1751000000,
            costWei: BigInt.from(1000000000000000), // 0.001 ETH
          ),
          SmartAccountActivity(
            type: SmartAccountActivityType.deviceRegistered,
            hash: '0x${'b2' * 32}',
            blockNumber: 200,
            logIndex: 0,
            timestamp: 1751000100,
            costWei: BigInt.from(2000000000000000), // 0.002 ETH
          ),
        ],
      ),
    );

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Session created'), findsOneWidget);
    expect(find.text('Device registered'), findsOneWidget);
  });

  testWidgets('deposit mostra QR code e o endereço da smart account',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Deposit'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(smartAccountAddress.hex), findsOneWidget);
  });

  testWidgets(
      'withdraw com sucesso chama SessionCreator.withdraw e fecha o sheet',
      (tester) async {
    when(() => mockSessionCreator.withdraw(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          destination: any(named: 'destination'),
          amountWei: any(named: 'amountWei'),
        )).thenAnswer((_) async => const SessionCreationResult(
          userOpHash: '0xUserOpHashXYZ',
          transactionHash: '0xTxHash',
        ));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Destination address'),
      '0xcccccccccccccccccccccccccccccccccccccccc',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount (ETH)'), '0.01');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw').last);
    await tester.pumpAndSettle();

    verify(() => mockSessionCreator.withdraw(
          smartAccountAddress: smartAccountAddress,
          destination: EthereumAddress.fromHex(
              '0xcccccccccccccccccccccccccccccccccccccccc'),
          amountWei: BigInt.from(10000000000000000), // 0.01 ETH em wei
        )).called(1);

    expect(find.text('Withdrawal sent!'), findsOneWidget);
  });

  testWidgets('withdraw com falha mostra erro inline, sem fechar o sheet',
      (tester) async {
    when(() => mockSessionCreator.withdraw(
          smartAccountAddress: any(named: 'smartAccountAddress'),
          destination: any(named: 'destination'),
          amountWei: any(named: 'amountWei'),
        )).thenThrow(Exception('bundler rejected the UserOperation'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Destination address'),
      '0xcccccccccccccccccccccccccccccccccccccccc',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount (ETH)'), '0.01');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Withdraw').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not send the withdrawal. Make sure your account has enough ETH for gas.',
      ),
      findsOneWidget,
    );
  });

  group('username não persistido (achado real, Sessão 134)', () {
    // identityId já pareado, mas o username nunca foi salvo (o fetch em
    // background do pareamento original falhou uma vez, sem retry) — antes
    // do fix, isso travava saldo/atividade pra sempre.
    setUp(() {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockStorage.savePairedUsername(any())).thenAnswer((_) async {});
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenAnswer((_) async => 'alice');
    });

    testWidgets('resolve o username on-chain, persiste e carrega o saldo',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      verify(() => mockBlockchain.getUsernameForIdentity(BigInt.one)).called(1);
      verify(() => mockStorage.savePairedUsername('alice')).called(1);
      expect(find.text('0.1230 ETH'), findsOneWidget);
    });

    testWidgets(
        'falha ao resolver o username não trava a tela (fica pra próximo load)',
        (tester) async {
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenThrow(Exception('log scan timed out'));

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      verifyNever(() => mockStorage.savePairedUsername(any()));
      expect(find.text('0.1230 ETH'), findsNothing);
      // A tela segue de pé (sem crash, sem travar em loading) mesmo sem saldo.
      expect(find.text('Balance'), findsOneWidget);
    });
  });

  testWidgets('botão Refresh limpa o cache e re-escaneia', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // O botão fica abaixo do fold no viewport padrão de teste (Balance +
    // Cost by type acima dele dentro da ListView) — precisa scrollar até
    // ele ficar visível antes de tocar.
    final refreshButton = find.widgetWithText(TextButton, 'Refresh');
    await tester.ensureVisible(refreshButton);
    await tester.pumpAndSettle();

    await tester.tap(refreshButton);
    await tester.pumpAndSettle();

    verify(() => mockActivityCacheService.clear(BigInt.one)).called(1);
    // Uma vez no load inicial, outra no rescan.
    verify(() => mockActivityScanner.scan(
          identityId: BigInt.one,
          fromBlock: any(named: 'fromBlock'),
          toBlock: any(named: 'toBlock'),
          onChunkScanned: any(named: 'onChunkScanned'),
        )).called(2);
  });
}

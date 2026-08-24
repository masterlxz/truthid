import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/screens/pair_device_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/vault_key_service.dart';
import 'package:truthid_mobile/services/wallet_connect_service.dart';

class MockWalletConnectService extends Mock implements WalletConnectService {}

class MockBlockchainService extends Mock implements BlockchainService {}

class MockVaultKeyService extends Mock implements VaultKeyService {}

class MockEciesService extends Mock implements EciesService {}

void main() {
  late MockWalletConnectService mockWc;
  late MockBlockchainService mockBlockchain;
  late MockVaultKeyService mockVaultKey;
  late MockEciesService mockEcies;
  late PairDeviceFlow flow;

  final owner =
      EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
  final controller =
      EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');
  final devicePubKey =
      EthereumAddress.fromHex('0x3333333333333333333333333333333333333333');

  const scanned = ScannedDevicePayload(
    pubKey: '0x3333333333333333333333333333333333333333',
    encryptionKey: '02aabbcc',
    label: 'New phone',
  );

  setUpAll(() {
    registerFallbackValue(controller);
    registerFallbackValue(devicePubKey);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(<EthereumAddress>[]);
    registerFallbackValue(<BigInt>[]);
    registerFallbackValue(<Uint8List>[]);
  });

  setUp(() {
    mockWc = MockWalletConnectService();
    mockBlockchain = MockBlockchainService();
    mockVaultKey = MockVaultKeyService();
    mockEcies = MockEciesService();

    flow = PairDeviceFlow(
      username: 'alice',
      onChange: () {},
      walletConnect: mockWc,
      blockchain: mockBlockchain,
      vaultKeyService: mockVaultKey,
      ecies: mockEcies,
    );

    when(() => mockWc.connectedAddress).thenReturn(owner.hex);
    when(() => mockWc.dispose()).thenAnswer((_) async {});
    flow.connectedAddress = owner.hex;
    flow.controller = controller;
    flow.setScannedDevice(scanned);

    when(() => mockBlockchain.buildDeviceCommitment(
          devicePubKey: any(named: 'devicePubKey'),
          salt: any(named: 'salt'),
          smartAccount: any(named: 'smartAccount'),
        )).thenReturn(Uint8List(32));
    when(() => mockBlockchain.buildCommitDeviceCalldata(any()))
        .thenReturn(Uint8List(4));
    when(() => mockBlockchain.buildExecuteCalldata(
          dest: any(named: 'dest'),
          value: any(named: 'value'),
          func: any(named: 'func'),
        )).thenReturn(Uint8List(4));
    when(() => mockBlockchain.buildRegisterDeviceCalldata(
          devicePubKey: any(named: 'devicePubKey'),
          label: any(named: 'label'),
          salt: any(named: 'salt'),
          encryptedVaultKey: any(named: 'encryptedVaultKey'),
        )).thenReturn(Uint8List(4));
    when(() => mockBlockchain.buildAddDeviceCalldata(any()))
        .thenReturn(Uint8List(4));
    when(() => mockBlockchain.buildExecuteBatchCalldata(
          dest: any(named: 'dest'),
          value: any(named: 'value'),
          func: any(named: 'func'),
        )).thenReturn(Uint8List(4));
  });

  group('pairDevice — sequência completa (happy path)', () {
    testWidgets('termina em done', (tester) async {
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6)); // flush waitingReveal
      await future;

      expect(flow.step, PairDeviceStep.done);
      expect(flow.errorMessage, isNull);
    });

    testWidgets('registerDevice + addDevice sempre no mesmo executeBatch',
        (tester) async {
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await future;

      verify(() => mockBlockchain.buildExecuteBatchCalldata(
            dest: [
              EthereumAddress.fromHex(BlockchainService.deviceRegistryAddress),
              controller,
            ],
            value: [BigInt.zero, BigInt.zero],
            func: any(named: 'func'),
          )).called(1);
      // Nunca chama sendTransaction pro DeviceRegistry direto — sempre pra
      // smart account (via execute/executeBatch).
      verify(() => mockWc.sendTransaction(
            to: controller.hex,
            data: any(named: 'data'),
          )).called(2); // commit + reveal
    });

    testWidgets('cifra a vault key quando encryptionKey está disponível',
        (tester) async {
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await future;

      verify(() => mockEcies.encrypt(any(), '02aabbcc')).called(1);
    });
  });

  group('pairDevice — fallback de vault key', () {
    testWidgets('sem encryptionKey no QR — não tenta cifrar, segue best-effort',
        (tester) async {
      flow.setScannedDevice(const ScannedDevicePayload(
        pubKey: '0x3333333333333333333333333333333333333333',
        encryptionKey: null,
        label: 'New phone',
      ));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await future;

      expect(flow.step, PairDeviceStep.done);
      verifyNever(() => mockEcies.encrypt(any(), any()));
      verify(() => mockBlockchain.buildRegisterDeviceCalldata(
            devicePubKey: any(named: 'devicePubKey'),
            label: any(named: 'label'),
            salt: any(named: 'salt'),
            encryptedVaultKey: Uint8List(0),
          )).called(1);
    });

    testWidgets('vault key indisponível — não aborta o pareamento',
        (tester) async {
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenThrow(Exception('no vault key stored'));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await future;

      expect(flow.step, PairDeviceStep.done);
      verify(() => mockBlockchain.buildRegisterDeviceCalldata(
            devicePubKey: any(named: 'devicePubKey'),
            label: any(named: 'label'),
            salt: any(named: 'salt'),
            encryptedVaultKey: Uint8List(0),
          )).called(1);
    });
  });

  group('pairDevice — commit revertido', () {
    testWidgets('vira errorMessage, nunca tenta o reveal', (tester) async {
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => false); // commit reverteu

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await future;

      expect(flow.step, PairDeviceStep.form);
      expect(flow.errorMessage, isNotNull);
      verify(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).called(1); // só o commit, nunca chega no reveal
    });
  });

  group('pairDevice — reveal revertido (RevealTooEarly)', () {
    testWidgets('retenta 1x automaticamente e recupera', (tester) async {
      var sendCalls = 0;
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async {
        sendCalls++;
        return '0xtxhash$sendCalls';
      });
      // commit ok (call 1); reveal falha na 1a tentativa (call 2), ok na 2a (call 3).
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash1'))
          .thenAnswer((_) async => true);
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash2'))
          .thenAnswer((_) async => false);
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash3'))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6)); // waitingReveal
      await tester.pump(const Duration(seconds: 4)); // retentativa (+3s)
      await future;

      expect(flow.step, PairDeviceStep.done);
      expect(sendCalls, 3);
    });

    testWidgets('falha nas 2 tentativas — vira errorMessage', (tester) async {
      var sendCalls = 0;
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async {
        sendCalls++;
        return '0xtxhash$sendCalls';
      });
      // commit ok (call 1); reveal falha nas 2 tentativas (calls 2 e 3).
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash1'))
          .thenAnswer((_) async => true);
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash2'))
          .thenAnswer((_) async => false);
      when(() => mockBlockchain.isTransactionConfirmed('0xtxhash3'))
          .thenAnswer((_) async => false);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final future = flow.pairDevice();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 4));
      await future;

      expect(flow.step, PairDeviceStep.form);
      expect(flow.errorMessage, isNotNull);
    });
  });

  group('pairDevice — guarda de disparo duplo', () {
    testWidgets('2 chamadas concorrentes só rodam a sequência 1 vez',
        (tester) async {
      var commitCalls = 0;
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async {
        commitCalls++;
        return '0xtxhash';
      });
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockVaultKey.deriveVaultKey())
          .thenAnswer((_) async => Uint8List(32));
      when(() => mockEcies.encrypt(any(), any()))
          .thenAnswer((_) async => Uint8List(93));

      final f1 = flow.pairDevice();
      final f2 = flow.pairDevice(); // dispara enquanto f1 ainda roda
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await Future.wait([f1, f2]);

      expect(commitCalls, 2); // commit + reveal de uma única sequência
    });
  });
}

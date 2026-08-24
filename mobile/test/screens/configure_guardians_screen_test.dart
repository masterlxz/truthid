import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/screens/configure_guardians_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/wallet_connect_service.dart';

class MockWalletConnectService extends Mock implements WalletConnectService {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  late MockWalletConnectService mockWc;
  late MockBlockchainService mockBlockchain;
  late ConfigureGuardiansFlow flow;
  int notifyCount = 0;

  final owner =
      EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
  final controller =
      EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');
  final guardian1 =
      EthereumAddress.fromHex('0x3333333333333333333333333333333333333333');
  final guardian2 =
      EthereumAddress.fromHex('0x4444444444444444444444444444444444444444');

  setUpAll(() {
    registerFallbackValue(controller);
    registerFallbackValue(<EthereumAddress>[]);
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockWc = MockWalletConnectService();
    mockBlockchain = MockBlockchainService();
    notifyCount = 0;

    flow = ConfigureGuardiansFlow(
      username: 'alice',
      onChange: () => notifyCount++,
      walletConnect: mockWc,
      blockchain: mockBlockchain,
    );

    when(() => mockWc.connectedAddress).thenReturn(owner.hex);
    when(() => mockWc.dispose()).thenAnswer((_) async {});
    flow.connectedAddress = owner.hex;
    flow.controller = controller;
  });

  group('submit — sequência completa (happy path)', () {
    setUp(() {
      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: any(named: 'username'),
            guardians: any(named: 'guardians'),
            threshold: any(named: 'threshold'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildExecuteCalldata(
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            func: any(named: 'func'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
    });

    test('termina em done', () async {
      await flow.submit(guardians: [guardian1, guardian2], threshold: 2);

      expect(flow.step, ConfigureGuardiansStep.done);
      expect(flow.errorMessage, isNull);
    });

    test('envia configureGuardians via execute() na smart account, não '
        'direto no RecoveryManager', () async {
      await flow.submit(guardians: [guardian1, guardian2], threshold: 2);

      verify(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: 'alice',
            guardians: [guardian1, guardian2],
            threshold: BigInt.two,
          )).called(1);
      verify(() => mockBlockchain.buildExecuteCalldata(
            dest: EthereumAddress.fromHex(
                BlockchainService.recoveryManagerAddress),
            value: BigInt.zero,
            func: any(named: 'func'),
          )).called(1);
      verify(() => mockWc.sendTransaction(
            to: controller.hex,
            data: any(named: 'data'),
          )).called(1);
    });

    test('checa proposta ativa antes de gastar gas', () async {
      await flow.submit(guardians: [guardian1, guardian2], threshold: 2);

      verify(() => mockBlockchain.getProposal('alice')).called(1);
    });
  });

  group('submit — bloqueio por proposta ativa', () {
    test('não envia transação se há proposta ativa', () async {
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
        (_) async => RecoveryProposal(
          proposedBy: '0x5555555555555555555555555555555555555555',
          newController: '0x6666666666666666666666666666666666666666',
          proposedAt: BigInt.zero,
          approvalCount: BigInt.one,
          executed: false,
          cancelled: false,
        ),
      );

      await flow.submit(guardians: [guardian1, guardian2], threshold: 2);

      expect(flow.step, ConfigureGuardiansStep.form);
      expect(flow.errorMessage, isNotNull);
      expect(flow.hasActiveProposal, isTrue);
      verifyNever(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          ));
    });

    test('proposta já executada não bloqueia', () async {
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
        (_) async => RecoveryProposal(
          proposedBy: '0x5555555555555555555555555555555555555555',
          newController: '0x6666666666666666666666666666666666666666',
          proposedAt: BigInt.zero,
          approvalCount: BigInt.one,
          executed: true,
          cancelled: false,
        ),
      );
      when(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: any(named: 'username'),
            guardians: any(named: 'guardians'),
            threshold: any(named: 'threshold'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildExecuteCalldata(
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            func: any(named: 'func'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      await flow.submit(guardians: [guardian1, guardian2], threshold: 2);

      expect(flow.step, ConfigureGuardiansStep.done);
    });
  });

  group('submit — guarda de disparo duplo', () {
    test('2 chamadas concorrentes só rodam a sequência 1 vez', () async {
      var proposalCalls = 0;
      when(() => mockBlockchain.getProposal('alice')).thenAnswer((_) async {
        proposalCalls++;
        await Future.delayed(const Duration(milliseconds: 30));
        return null;
      });
      when(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: any(named: 'username'),
            guardians: any(named: 'guardians'),
            threshold: any(named: 'threshold'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildExecuteCalldata(
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            func: any(named: 'func'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      final f1 = flow.submit(guardians: [guardian1], threshold: 1);
      final f2 = flow.submit(guardians: [guardian1], threshold: 1);
      await Future.wait([f1, f2]);

      expect(proposalCalls, 1);
    });
  });

  group('submit — caminho de erro', () {
    test('transação revertida vira errorMessage e volta pro form', () async {
      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: any(named: 'username'),
            guardians: any(named: 'guardians'),
            threshold: any(named: 'threshold'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildExecuteCalldata(
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            func: any(named: 'func'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => false); // reverteu

      await flow.submit(guardians: [guardian1], threshold: 1);

      expect(flow.step, ConfigureGuardiansStep.form);
      expect(flow.errorMessage, isNotNull);
    });

    test('libera a guarda depois de um erro — dá pra tentar de novo',
        () async {
      when(() => mockBlockchain.getProposal('alice'))
          .thenThrow(Exception('RPC indisponível'));

      await flow.submit(guardians: [guardian1], threshold: 1);
      expect(flow.isBusy, isFalse);

      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.buildConfigureGuardiansCalldata(
            username: any(named: 'username'),
            guardians: any(named: 'guardians'),
            threshold: any(named: 'threshold'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildExecuteCalldata(
            dest: any(named: 'dest'),
            value: any(named: 'value'),
            func: any(named: 'func'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      await flow.submit(guardians: [guardian1], threshold: 1);
      expect(flow.step, ConfigureGuardiansStep.done);
    });
  });
}

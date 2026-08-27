import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/screens/act_as_guardian_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/wallet_connect_service.dart';

import '../utils/l10n_test_app.dart';

class MockWalletConnectService extends Mock implements WalletConnectService {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  late MockWalletConnectService mockWc;
  late MockBlockchainService mockBlockchain;
  late ActAsGuardianFlow flow;

  final owner =
      EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
  final newController =
      EthereumAddress.fromHex('0x9999999999999999999999999999999999999999');

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'));
  });

  setUp(() {
    mockWc = MockWalletConnectService();
    mockBlockchain = MockBlockchainService();

    flow = ActAsGuardianFlow(
      onChange: () {},
      walletConnect: mockWc,
      blockchain: mockBlockchain,
    );

    when(() => mockWc.connectedAddress).thenReturn(owner.hex);
    when(() => mockWc.dispose()).thenAnswer((_) async {});
    flow.connectedAddress = owner.hex;
  });

  group('loadTarget — getters derivados', () {
    test('isGuardian true quando o endereço conectado está na lista '
        '(case-insensitive)', () async {
      when(() => mockBlockchain.getGuardianConfig('alice')).thenAnswer(
          (_) async => (guardians: [owner.hex.toUpperCase()], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));

      await flow.loadTarget('alice');

      expect(flow.isGuardian, isTrue);
      expect(flow.proposalStatus, ProposalLifecycle.none);
    });

    test('isGuardian false quando o endereço conectado não está na lista',
        () async {
      when(() => mockBlockchain.getGuardianConfig('alice')).thenAnswer(
          (_) async => (guardians: ['0x2222222222222222222222222222222222222222'], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));

      await flow.loadTarget('alice');

      expect(flow.isGuardian, isFalse);
      verifyNever(() => mockBlockchain.hasGuardianApproved(any(), any()));
    });

    test('busca hasGuardianApproved só quando é guardião e há proposta ativa',
        () async {
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer((_) async => RecoveryProposal(
            proposedBy: '0x3333333333333333333333333333333333333333',
            newController: newController.hex,
            proposedAt: BigInt.zero,
            approvalCount: BigInt.zero,
            executed: false,
            cancelled: false,
          ));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));
      when(() => mockBlockchain.hasGuardianApproved('alice', owner.hex))
          .thenAnswer((_) async => true);

      await flow.loadTarget('alice');

      expect(flow.proposalStatus, ProposalLifecycle.active);
      expect(flow.targetHasApproved, isTrue);
      verify(() => mockBlockchain.hasGuardianApproved('alice', owner.hex))
          .called(1);
    });

    test('proposalStatus reflete executed/cancelled', () async {
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer((_) async => RecoveryProposal(
            proposedBy: '0x3333333333333333333333333333333333333333',
            newController: newController.hex,
            proposedAt: BigInt.zero,
            approvalCount: BigInt.one,
            executed: true,
            cancelled: false,
          ));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));

      await flow.loadTarget('alice');

      expect(flow.proposalStatus, ProposalLifecycle.executed);
      // proposta já finalizada — não busca hasGuardianApproved
      verifyNever(() => mockBlockchain.hasGuardianApproved(any(), any()));
    });
  });

  group('canExecute', () {
    RecoveryProposal proposalWith({required BigInt approvalCount, required BigInt proposedAt}) =>
        RecoveryProposal(
          proposedBy: '0x3333333333333333333333333333333333333333',
          newController: newController.hex,
          proposedAt: proposedAt,
          approvalCount: approvalCount,
          executed: false,
          cancelled: false,
        );

    test('true quando threshold atingido e timelock decorrido', () async {
      final proposedAt = BigInt.from(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1000000);
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.two));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
          (_) async => proposalWith(approvalCount: BigInt.two, proposedAt: proposedAt));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800)); // 7 dias
      when(() => mockBlockchain.hasGuardianApproved(any(), any()))
          .thenAnswer((_) async => true);

      await flow.loadTarget('alice');

      expect(flow.canExecute, isTrue);
    });

    test('false quando threshold não atingido', () async {
      final proposedAt = BigInt.from(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1000000);
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.two));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
          (_) async => proposalWith(approvalCount: BigInt.one, proposedAt: proposedAt));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));
      when(() => mockBlockchain.hasGuardianApproved(any(), any()))
          .thenAnswer((_) async => false);

      await flow.loadTarget('alice');

      expect(flow.canExecute, isFalse);
    });

    test('false quando timelock ainda não decorreu', () async {
      final proposedAt =
          BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.two));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
          (_) async => proposalWith(approvalCount: BigInt.two, proposedAt: proposedAt));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));
      when(() => mockBlockchain.hasGuardianApproved(any(), any()))
          .thenAnswer((_) async => true);

      await flow.loadTarget('alice');

      expect(flow.canExecute, isFalse);
    });

    test('não é guardião-gated — false mesmo sem ser guardião não impede '
        'true quando as demais condições batem', () async {
      final proposedAt = BigInt.from(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1000000);
      when(() => mockBlockchain.getGuardianConfig('alice')).thenAnswer(
          (_) async => (guardians: ['0x2222222222222222222222222222222222222222'], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer(
          (_) async => proposalWith(approvalCount: BigInt.one, proposedAt: proposedAt));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));

      await flow.loadTarget('alice');

      expect(flow.isGuardian, isFalse);
      expect(flow.canExecute, isTrue);
    });
  });

  group('propose', () {
    setUp(() async {
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice'))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));
      await flow.loadTarget('alice');
    });

    test('sequência completa — envia direto no RecoveryManager, sem execute()',
        () async {
      when(() => mockBlockchain.buildProposeRecoveryCalldata(
            username: any(named: 'username'),
            newController: any(named: 'newController'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      await flow.propose(newController);

      verify(() => mockBlockchain.buildProposeRecoveryCalldata(
            username: 'alice',
            newController: newController,
          )).called(1);
      verify(() => mockWc.sendTransaction(
            to: BlockchainService.recoveryManagerAddress,
            data: any(named: 'data'),
          )).called(1);
      expect(flow.errorMessage, isNull);
    });

    test('guarda de disparo duplo', () async {
      var calls = 0;
      when(() => mockBlockchain.buildProposeRecoveryCalldata(
            username: any(named: 'username'),
            newController: any(named: 'newController'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async {
        calls++;
        await Future.delayed(const Duration(milliseconds: 20));
        return '0xtxhash';
      });
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      final f1 = flow.propose(newController);
      final f2 = flow.propose(newController);
      await Future.wait([f1, f2]);

      expect(calls, 1);
    });

    test('transação revertida vira errorMessage', () async {
      when(() => mockBlockchain.buildProposeRecoveryCalldata(
            username: any(named: 'username'),
            newController: any(named: 'newController'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => false);

      await flow.propose(newController);

      expect(flow.errorMessage, isNotNull);
    });
  });

  group('approve/execute', () {
    setUp(() async {
      when(() => mockBlockchain.getGuardianConfig('alice'))
          .thenAnswer((_) async => (guardians: [owner.hex], threshold: BigInt.one));
      when(() => mockBlockchain.getProposal('alice')).thenAnswer((_) async => RecoveryProposal(
            proposedBy: '0x3333333333333333333333333333333333333333',
            newController: newController.hex,
            proposedAt: BigInt.zero,
            approvalCount: BigInt.zero,
            executed: false,
            cancelled: false,
          ));
      when(() => mockBlockchain.getTimelock())
          .thenAnswer((_) async => BigInt.from(604800));
      when(() => mockBlockchain.hasGuardianApproved('alice', owner.hex))
          .thenAnswer((_) async => false);
      await flow.loadTarget('alice');
    });

    test('approve envia direto no RecoveryManager e recarrega o alvo',
        () async {
      when(() => mockBlockchain.buildApproveRecoveryCalldata('alice'))
          .thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      await flow.approve();

      verify(() => mockWc.sendTransaction(
            to: BlockchainService.recoveryManagerAddress,
            data: any(named: 'data'),
          )).called(1);
      // recarregou o alvo — getProposal chamado de novo (setUp + refresh)
      verify(() => mockBlockchain.getProposal('alice')).called(2);
    });

    test('execute envia direto no RecoveryManager', () async {
      when(() => mockBlockchain.buildExecuteRecoveryCalldata('alice'))
          .thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);

      await flow.execute();

      verify(() => mockWc.sendTransaction(
            to: BlockchainService.recoveryManagerAddress,
            data: any(named: 'data'),
          )).called(1);
      expect(flow.errorMessage, isNull);
    });
  });

  group('ActAsGuardianScreen — reatividade do campo de username', () {
    // Regressão: o botão "Look up" só reconstruía via `flow.onChange`
    // (eventos do fluxo), nunca ao digitar — ficava preso desabilitado
    // mesmo com texto no campo (achado P82 #1).
    testWidgets('digitar no campo habilita o botão Look up', (tester) async {
      await tester.pumpWidget(wrapForTest(ActAsGuardianScreen(flow: flow)));

      final lookUpButton =
          find.widgetWithText(ElevatedButton, 'Look up');
      expect(
          tester.widget<ElevatedButton>(lookUpButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pump();

      expect(
          tester.widget<ElevatedButton>(lookUpButton).onPressed, isNotNull);
    });
  });
}

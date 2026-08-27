import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/wallet_connect_service.dart';
import '../theme.dart';
import '../utils/wallet_connect_flow_mixin.dart';

enum ActAsGuardianStep { form, connectingWallet, loadingTarget, submitting }

enum ProposalLifecycle { none, active, executed, cancelled }

/// Máquina de estados pra agir como guardião de OUTRA identidade pelo Mobile
/// — propor/aprovar/executar uma recovery social. Espelha a seção "Act as
/// guardian for another identity" de `GuardianManagement.tsx` no Desktop
/// (linhas 324-474), incluindo a UX exata: diferente de `ConfigureGuardiansFlow`
/// (owner-gated, via `execute()` na smart account), aqui as 3 escritas —
/// `proposeRecovery`/`approveRecovery`/`executeRecovery` — são chamadas
/// DIRETAS no `RecoveryManager`, assinadas pela wallet do guardião. Nunca
/// passam pela smart account da identidade alvo.
class ActAsGuardianFlow with WalletConnectFlowMixin<ActAsGuardianStep> {
  @override
  final WalletConnectService walletConnect;
  @override
  final BlockchainService blockchain;
  final void Function() onChange;

  ActAsGuardianFlow({
    required this.onChange,
    WalletConnectService? walletConnect,
    BlockchainService? blockchain,
  })  : walletConnect = walletConnect ?? WalletConnectService(),
        blockchain = blockchain ?? BlockchainService();

  bool _busy = false;
  bool get isBusy => _busy;
  @override
  bool get busy => _busy;
  @override
  set busy(bool value) => _busy = value;

  ActAsGuardianStep step = ActAsGuardianStep.form;
  @override
  String? errorMessage;
  @override
  String? connectedAddress;

  String? targetUsername;
  List<String>? targetGuardians;
  BigInt? targetThreshold;
  RecoveryProposal? targetProposal;
  BigInt? targetTimelock;
  bool targetHasApproved = false;

  bool get isGuardian =>
      connectedAddress != null &&
      targetGuardians != null &&
      targetGuardians!
          .any((g) => g.toLowerCase() == connectedAddress!.toLowerCase());

  ProposalLifecycle get proposalStatus {
    final p = targetProposal;
    if (p == null) return ProposalLifecycle.none;
    if (p.executed) return ProposalLifecycle.executed;
    if (p.cancelled) return ProposalLifecycle.cancelled;
    return ProposalLifecycle.active;
  }

  // Não é guardião-gated de propósito — qualquer um pode executar depois do
  // threshold + timelock, mesma regra do contrato (RecoveryManager.sol:240).
  bool get canExecute {
    final p = targetProposal;
    final threshold = targetThreshold;
    final timelock = targetTimelock;
    if (proposalStatus != ProposalLifecycle.active ||
        p == null ||
        threshold == null ||
        threshold == BigInt.zero ||
        timelock == null) {
      return false;
    }
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return p.approvalCount >= threshold && now >= p.proposedAt + timelock;
  }

  void _set(ActAsGuardianStep newStep) {
    step = newStep;
    onChange();
  }

  @override
  ActAsGuardianStep get connectingWalletStep =>
      ActAsGuardianStep.connectingWallet;
  @override
  ActAsGuardianStep get formStep => ActAsGuardianStep.form;
  @override
  void setStep(ActAsGuardianStep newStep) => _set(newStep);

  Future<void> loadTarget(String username) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    targetUsername = username;
    _set(ActAsGuardianStep.loadingTarget);
    try {
      final results = await Future.wait([
        blockchain.getGuardianConfig(username),
        blockchain.getProposal(username),
        blockchain.getTimelock(),
      ]);
      final config =
          results[0] as ({List<String> guardians, BigInt threshold})?;
      targetGuardians = config?.guardians;
      targetThreshold = config?.threshold;
      targetProposal = results[1] as RecoveryProposal?;
      targetTimelock = results[2] as BigInt?;

      targetHasApproved = false;
      if (isGuardian &&
          proposalStatus == ProposalLifecycle.active &&
          connectedAddress != null) {
        targetHasApproved =
            await blockchain.hasGuardianApproved(username, connectedAddress!);
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      _busy = false;
      _set(ActAsGuardianStep.form);
    }
  }

  /// `newController` já validado pelo widget (mesmo padrão de
  /// `PairDeviceFlow.pairDevice`/`ConfigureGuardiansFlow.submit` — validação
  /// sintática fica na UI, aqui só entra o que precisa de rede).
  Future<void> propose(EthereumAddress newController) async {
    if (_busy) return;
    final username = targetUsername;
    if (username == null) return;
    _busy = true;
    errorMessage = null;
    try {
      _set(ActAsGuardianStep.submitting);
      final calldata = blockchain.buildProposeRecoveryCalldata(
        username: username,
        newController: newController,
      );
      final txHash = await walletConnect.sendTransaction(
        to: BlockchainService.recoveryManagerAddress,
        data: bytesToHex(calldata, include0x: true),
      );
      final ok = await waitForReceipt(txHash);
      if (!ok) throw Exception('proposeRecovery transaction reverted on-chain.');
      _busy = false;
      await loadTarget(username);
    } catch (e) {
      errorMessage = e.toString();
      _busy = false;
      _set(ActAsGuardianStep.form);
    }
  }

  Future<void> approve() async {
    if (_busy) return;
    final username = targetUsername;
    if (username == null) return;
    _busy = true;
    errorMessage = null;
    try {
      _set(ActAsGuardianStep.submitting);
      final calldata = blockchain.buildApproveRecoveryCalldata(username);
      final txHash = await walletConnect.sendTransaction(
        to: BlockchainService.recoveryManagerAddress,
        data: bytesToHex(calldata, include0x: true),
      );
      final ok = await waitForReceipt(txHash);
      if (!ok) throw Exception('approveRecovery transaction reverted on-chain.');
      _busy = false;
      await loadTarget(username);
    } catch (e) {
      errorMessage = e.toString();
      _busy = false;
      _set(ActAsGuardianStep.form);
    }
  }

  Future<void> execute() async {
    if (_busy) return;
    final username = targetUsername;
    if (username == null) return;
    _busy = true;
    errorMessage = null;
    try {
      _set(ActAsGuardianStep.submitting);
      final calldata = blockchain.buildExecuteRecoveryCalldata(username);
      final txHash = await walletConnect.sendTransaction(
        to: BlockchainService.recoveryManagerAddress,
        data: bytesToHex(calldata, include0x: true),
      );
      final ok = await waitForReceipt(txHash);
      if (!ok) throw Exception('executeRecovery transaction reverted on-chain.');
      _busy = false;
      await loadTarget(username);
    } catch (e) {
      errorMessage = e.toString();
      _busy = false;
      _set(ActAsGuardianStep.form);
    }
  }

  void dispose() {
    unawaited(walletConnect.dispose());
  }
}

class ActAsGuardianScreen extends StatefulWidget {
  // Injetável para testes — em produção usa o default.
  final ActAsGuardianFlow? flow;

  const ActAsGuardianScreen({super.key, this.flow});

  @override
  State<ActAsGuardianScreen> createState() => _ActAsGuardianScreenState();
}

class _ActAsGuardianScreenState extends State<ActAsGuardianScreen> {
  late final ActAsGuardianFlow _flow;
  final _usernameController = TextEditingController();
  final _newControllerController = TextEditingController();
  String? _addressError;

  @override
  void initState() {
    super.initState();
    _flow = widget.flow ??
        ActAsGuardianFlow(onChange: () {
          if (mounted) setState(() {});
        });
    // O botão "Look Up" habilita/desabilita conforme o texto digitado, mas
    // só reconstrói via `_flow.onChange` (eventos do fluxo, não digitação) —
    // sem este listener o botão fica preso no estado da última reconstrução.
    _usernameController.addListener(_onUsernameChanged);
  }

  void _onUsernameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onUsernameChanged);
    _flow.dispose();
    _usernameController.dispose();
    _newControllerController.dispose();
    super.dispose();
  }

  String _timeRemaining(BuildContext context, BigInt proposedAt, BigInt? timelock) {
    if (timelock == null) return '';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deadline = proposedAt.toInt() + timelock.toInt();
    if (now >= deadline) return context.l10n.guardianStatusScreenReadyToExecute;
    final diff = deadline - now;
    final d = diff ~/ 86400;
    final h = (diff % 86400) ~/ 3600;
    final m = (diff % 3600) ~/ 60;
    return context.l10n.guardianStatusScreenTimeRemaining(d, h, m);
  }

  void _handlePropose(BuildContext context) {
    setState(() => _addressError = null);
    late final EthereumAddress newController;
    try {
      newController =
          EthereumAddress.fromHex(_newControllerController.text.trim());
    } catch (_) {
      setState(() => _addressError =
          context.l10n.actAsGuardianScreenInvalidAddressError);
      return;
    }
    _flow.propose(newController);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _flow.isBusy;
    final connected = _flow.connectedAddress != null;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.actAsGuardianScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!connected) ...[
                ElevatedButton.icon(
                  onPressed: busy ? null : () => _flow.connectWallet(context),
                  icon: const Icon(Icons.account_balance_wallet),
                  label:
                      Text(context.l10n.actAsGuardianScreenConnectWalletButton),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.actAsGuardianScreenUsernameField,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: busy || _usernameController.text.trim().isEmpty
                          ? null
                          : () => _flow.loadTarget(
                              _usernameController.text.trim()),
                      child: Text(context.l10n.actAsGuardianScreenLookUpButton),
                    ),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
                if (!busy && _flow.targetUsername != null)
                  _buildTargetSection(context),
              ],
              if (_flow.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_flow.errorMessage!,
                    style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetSection(BuildContext context) {
    if (_flow.targetGuardians == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          context.l10n.actAsGuardianScreenNotGuardianFor(_flow.targetUsername!),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    if (!_flow.isGuardian) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          context.l10n.actAsGuardianScreenNotGuardianFor(_flow.targetUsername!),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    switch (_flow.proposalStatus) {
      case ProposalLifecycle.none:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.actAsGuardianScreenNoActiveRecoveryFor(
                  _flow.targetUsername!)),
              const SizedBox(height: 8),
              TextField(
                controller: _newControllerController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText:
                      context.l10n.actAsGuardianScreenNewControllerField,
                ),
              ),
              if (_addressError != null) ...[
                const SizedBox(height: 8),
                Text(_addressError!,
                    style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _handlePropose(context),
                child: Text(context.l10n.actAsGuardianScreenProposeButton),
              ),
            ],
          ),
        );

      case ProposalLifecycle.active:
        final p = _flow.targetProposal!;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(context.l10n.guardianStatusScreenProposedByLabel,
                  p.proposedBy),
              _row(context.l10n.guardianStatusScreenNewControllerLabel,
                  p.newController),
              _row(
                context.l10n.guardianStatusScreenApprovalsLabel,
                context.l10n.guardianStatusScreenApprovalsValue(
                    p.approvalCount.toString(),
                    (_flow.targetThreshold ?? BigInt.zero).toString()),
              ),
              _row(
                context.l10n.guardianStatusScreenTimelockLabel,
                _timeRemaining(context, p.proposedAt, _flow.targetTimelock),
              ),
              const SizedBox(height: 12),
              if (!_flow.targetHasApproved)
                ElevatedButton(
                  onPressed: () => _flow.approve(),
                  child: Text(context.l10n.actAsGuardianScreenApproveButton),
                )
              else
                Text(context.l10n.actAsGuardianScreenApprovedBadge,
                    style: const TextStyle(color: AppColors.success)),
              if (_flow.canExecute) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger),
                  onPressed: () => _flow.execute(),
                  child: Text(context.l10n.actAsGuardianScreenExecuteButton),
                ),
              ],
            ],
          ),
        );

      case ProposalLifecycle.executed:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(context.l10n.guardianStatusScreenRecoveryExecuted,
              style: const TextStyle(color: AppColors.success)),
        );

      case ProposalLifecycle.cancelled:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(context.l10n.guardianStatusScreenRecoveryCancelled,
              style: const TextStyle(color: AppColors.textMuted)),
        );
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value.startsWith('0x')
                  ? '${value.substring(0, 8)}…${value.substring(value.length - 4)}'
                  : value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

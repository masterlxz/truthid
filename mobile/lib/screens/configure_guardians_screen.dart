import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/wallet_connect_service.dart';
import '../theme.dart';

// Mesmo limite de RecoveryManager.MAX_GUARDIANS (contracts/src/RecoveryManager.sol).
const _maxGuardians = 20;

enum ConfigureGuardiansStep { form, connectingWallet, submitting, done }

/// Máquina de estados pra configurar (ou reconfigurar) os guardians da
/// própria identidade pelo Mobile (P68, fatia 2) — espelha
/// `GuardianManagement.tsx.handleConfigure` no Desktop: `configureGuardians`
/// é chamado através de `TruthIDAccount.execute` (não direto no
/// `RecoveryManager`), porque `_requireController` exige que `msg.sender`
/// seja a smart account, não a wallet externa conectada.
///
/// Validação sintática (endereço inválido, lista vazia, duplicata, threshold
/// fora do range, excesso de guardians) fica no widget — mesmo padrão de
/// `CreateIdentityScreen._handleCreate` (checagem trivial e local antes de
/// chamar o flow). Aqui só entra o que precisa de rede: confirmar que não há
/// proposta de recovery ativa antes de gastar gas numa tx que reverteria com
/// `ActiveProposalExists()`.
class ConfigureGuardiansFlow {
  final WalletConnectService walletConnect;
  final BlockchainService blockchain;
  final void Function() onChange;
  final String username;

  ConfigureGuardiansFlow({
    required this.username,
    required this.onChange,
    WalletConnectService? walletConnect,
    BlockchainService? blockchain,
  })  : walletConnect = walletConnect ?? WalletConnectService(),
        blockchain = blockchain ?? BlockchainService();

  bool _busy = false;
  bool get isBusy => _busy;

  ConfigureGuardiansStep step = ConfigureGuardiansStep.form;
  String? errorMessage;
  String? connectedAddress;
  EthereumAddress? controller;
  bool hasActiveProposal = false;

  void _set(ConfigureGuardiansStep newStep) {
    step = newStep;
    onChange();
  }

  Future<void> connectWallet(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    _set(ConfigureGuardiansStep.connectingWallet);
    try {
      await walletConnect.init(context);
      await walletConnect.openConnectModal();
      connectedAddress = walletConnect.connectedAddress;
      _set(ConfigureGuardiansStep.form);
    } catch (e) {
      errorMessage = e.toString();
      _set(ConfigureGuardiansStep.form);
    } finally {
      _busy = false;
    }
  }

  /// `guardians` já validado pelo widget (endereços parseados, sem
  /// duplicata, dentro do limite; `threshold` já dentro do range 1..N).
  Future<void> submit({
    required List<EthereumAddress> guardians,
    required int threshold,
  }) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    try {
      controller ??=
          (await blockchain.getIdentityByUsername(username))?.controller;
      final smartAccount = controller;
      if (smartAccount == null) {
        throw Exception('Could not resolve the smart account controller.');
      }

      final activeProposal = await blockchain.getProposal(username);
      if (activeProposal != null &&
          !activeProposal.executed &&
          !activeProposal.cancelled) {
        hasActiveProposal = true;
        throw Exception(
            'An active recovery proposal already exists for this identity — cancel it first.');
      }

      _set(ConfigureGuardiansStep.submitting);
      final configureCalldata = blockchain.buildConfigureGuardiansCalldata(
        username: username,
        guardians: guardians,
        threshold: BigInt.from(threshold),
      );
      final executeCalldata = blockchain.buildExecuteCalldata(
        dest:
            EthereumAddress.fromHex(BlockchainService.recoveryManagerAddress),
        value: BigInt.zero,
        func: configureCalldata,
      );
      final txHash = await walletConnect.sendTransaction(
        to: smartAccount.hex,
        data: bytesToHex(executeCalldata, include0x: true),
      );
      final ok = await _waitForReceipt(txHash);
      if (!ok) {
        throw Exception('configureGuardians transaction reverted on-chain.');
      }

      _set(ConfigureGuardiansStep.done);
    } catch (e) {
      errorMessage = e.toString();
      _set(ConfigureGuardiansStep.form);
    } finally {
      _busy = false;
    }
  }

  Future<bool> _waitForReceipt(
    String txHash, {
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final confirmed = await blockchain.isTransactionConfirmed(txHash);
      if (confirmed != null) return confirmed;
      await Future.delayed(pollInterval);
    }
    throw TimeoutException(
        'Transaction $txHash was not mined within $timeout.');
  }

  void dispose() {
    unawaited(walletConnect.dispose());
  }
}

class ConfigureGuardiansScreen extends StatefulWidget {
  final String username;
  final List<String>? initialGuardians;
  final BigInt? initialThreshold;
  // Injetável para testes — em produção usa o default.
  final ConfigureGuardiansFlow? flow;

  const ConfigureGuardiansScreen({
    super.key,
    required this.username,
    this.initialGuardians,
    this.initialThreshold,
    this.flow,
  });

  @override
  State<ConfigureGuardiansScreen> createState() =>
      _ConfigureGuardiansScreenState();
}

class _ConfigureGuardiansScreenState extends State<ConfigureGuardiansScreen> {
  late final ConfigureGuardiansFlow _flow;
  late final List<TextEditingController> _guardianControllers;
  late final TextEditingController _thresholdController;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _flow = widget.flow ??
        ConfigureGuardiansFlow(
          username: widget.username,
          onChange: () {
            if (mounted) setState(() {});
          },
        );

    final initial = widget.initialGuardians;
    _guardianControllers = (initial != null && initial.isNotEmpty)
        ? initial.map((g) => TextEditingController(text: g)).toList()
        : [TextEditingController()];
    _thresholdController = TextEditingController(
      text: (widget.initialThreshold ?? BigInt.one).toString(),
    );
  }

  @override
  void dispose() {
    _flow.dispose();
    for (final c in _guardianControllers) {
      c.dispose();
    }
    _thresholdController.dispose();
    super.dispose();
  }

  void _addGuardianField() {
    if (_guardianControllers.length >= _maxGuardians) return;
    setState(() => _guardianControllers.add(TextEditingController()));
  }

  void _removeGuardianField(int index) {
    setState(() {
      final removed = _guardianControllers.removeAt(index);
      removed.dispose();
      if (_guardianControllers.isEmpty) {
        _guardianControllers.add(TextEditingController());
      }
    });
  }

  Future<void> _handleSubmit() async {
    setState(() => _formError = null);

    final rawAddresses = _guardianControllers
        .map((c) => c.text.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    if (rawAddresses.isEmpty) {
      setState(() => _formError =
          context.l10n.configureGuardiansScreenEmptyGuardiansError);
      return;
    }
    if (rawAddresses.length > _maxGuardians) {
      setState(() => _formError =
          context.l10n.configureGuardiansScreenTooManyGuardiansError);
      return;
    }

    final seen = <String>{};
    for (final a in rawAddresses) {
      if (!seen.add(a.toLowerCase())) {
        setState(() => _formError =
            context.l10n.configureGuardiansScreenDuplicateGuardianError);
        return;
      }
    }

    final parsed = <EthereumAddress>[];
    for (final a in rawAddresses) {
      try {
        parsed.add(EthereumAddress.fromHex(a));
      } catch (_) {
        setState(() => _formError =
            context.l10n.configureGuardiansScreenInvalidAddressError);
        return;
      }
    }

    final threshold = int.tryParse(_thresholdController.text.trim());
    if (threshold == null || threshold < 1 || threshold > parsed.length) {
      setState(() => _formError =
          context.l10n.configureGuardiansScreenThresholdRangeError);
      return;
    }

    await _flow.submit(guardians: parsed, threshold: threshold);

    if (!mounted) return;
    if (_flow.step == ConfigureGuardiansStep.done &&
        _flow.errorMessage == null) {
      Navigator.of(context).pop(true);
    }
  }

  String _stepLabel(BuildContext context, ConfigureGuardiansStep step) {
    switch (step) {
      case ConfigureGuardiansStep.form:
        return '';
      case ConfigureGuardiansStep.connectingWallet:
        return context.l10n.configureGuardiansScreenStepConnecting;
      case ConfigureGuardiansStep.submitting:
        return context.l10n.configureGuardiansScreenStepSubmitting;
      case ConfigureGuardiansStep.done:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(context.l10n.configureGuardiansScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _flow.step == ConfigureGuardiansStep.done
            ? _buildDoneUI(context)
            : _buildFormUI(context),
      ),
    );
  }

  Widget _buildFormUI(BuildContext context) {
    final busy = _flow.isBusy;
    final connected = _flow.connectedAddress != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!connected) ...[
            ElevatedButton.icon(
              onPressed: busy ? null : () => _flow.connectWallet(context),
              icon: const Icon(Icons.account_balance_wallet),
              label: Text(
                  context.l10n.configureGuardiansScreenConnectWalletButton),
            ),
          ] else ...[
            Text(
              context.l10n.configureGuardiansScreenConnectedAddressLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _flow.connectedAddress!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.configureGuardiansScreenGuardiansLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _guardianControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _guardianControllers[i],
                        enabled: !busy,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          labelText: context
                              .l10n.configureGuardiansScreenAddressField,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : () => _removeGuardianField(i),
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: context
                          .l10n.configureGuardiansScreenRemoveGuardianTooltip,
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: busy ? null : _addGuardianField,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.configureGuardiansScreenAddGuardianButton),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _thresholdController,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.configureGuardiansScreenThresholdLabel,
                suffixText: context.l10n.configureGuardiansScreenThresholdOfSuffix(
                    _guardianControllers.length),
              ),
            ),
            const SizedBox(height: 24),
            if (busy) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stepLabel(context, _flow.step)),
            ] else
              ElevatedButton(
                onPressed: _handleSubmit,
                child: Text(context.l10n.configureGuardiansScreenSubmitButton),
              ),
          ],
          if (_formError != null) ...[
            const SizedBox(height: 16),
            Text(_formError!, style: const TextStyle(color: AppColors.danger)),
          ],
          if (_flow.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(_flow.errorMessage!,
                style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _buildDoneUI(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 72, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            context.l10n.configureGuardiansScreenSuccessMessage,
            style: const TextStyle(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.createIdentityScreenContinueButton),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/ecies_service.dart';
import '../services/vault_key_service.dart';
import '../services/wallet_connect_service.dart';
import '../theme.dart';
import '../utils/random_bytes.dart';
import 'scan_screen.dart';

enum PairDeviceStep {
  form,
  connectingWallet,
  committing,
  waitingReveal,
  revealing,
  done,
}

/// Payload lido do QR mostrado por `ShowDeviceQrScreen` no device novo —
/// mesmo formato `{action, pubKey, encryptionKey, label}` já usado desde o
/// fluxo original de pareamento pelo Desktop.
class ScannedDevicePayload {
  final String pubKey;
  final String? encryptionKey;
  final String label;

  const ScannedDevicePayload({
    required this.pubKey,
    required this.encryptionKey,
    required this.label,
  });

  static ScannedDevicePayload? tryParse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['action'] != 'truthid-device') return null;
      final pubKey = json['pubKey'] as String?;
      if (pubKey == null || pubKey.isEmpty) return null;
      return ScannedDevicePayload(
        pubKey: pubKey,
        encryptionKey: json['encryptionKey'] as String?,
        label: (json['label'] as String?) ?? 'Device',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Máquina de estados do fluxo de parear um NOVO device pelo Mobile (P68,
/// fatia 2) — espelha o commit-reveal de `PairDevice.tsx` no Desktop, mas
/// aqui é este device (já pareado, com uma wallet externa conectada via
/// WalletConnect) que assume o papel ativo, autorizando o device escaneado.
///
/// **`registerDevice` e `addDevice` sempre vão juntos no mesmo
/// `executeBatch`, nunca separados** — achado real do P52/P53 (Sessão 205):
/// `authorizedDevices` é um mapping separado dentro da própria smart
/// account, é ele (não o `DeviceRegistry`) que `_validateSignature` checa;
/// um device "registrado" sem `addDevice` fica incapaz de assinar qualquer
/// UserOp pra própria conta.
class PairDeviceFlow {
  final WalletConnectService walletConnect;
  final BlockchainService blockchain;
  final VaultKeyService vaultKeyService;
  final EciesService ecies;
  final void Function() onChange;
  final String username;

  PairDeviceFlow({
    required this.username,
    required this.onChange,
    WalletConnectService? walletConnect,
    BlockchainService? blockchain,
    VaultKeyService? vaultKeyService,
    EciesService? ecies,
  })  : walletConnect = walletConnect ?? WalletConnectService(),
        blockchain = blockchain ?? BlockchainService(),
        vaultKeyService = vaultKeyService ?? VaultKeyService(),
        ecies = ecies ?? EciesService();

  bool _busy = false;
  bool get isBusy => _busy;

  PairDeviceStep step = PairDeviceStep.form;
  String? errorMessage;
  String? connectedAddress;
  EthereumAddress? controller;
  ScannedDevicePayload? scannedDevice;

  void _set(PairDeviceStep newStep) {
    step = newStep;
    onChange();
  }

  void setScannedDevice(ScannedDevicePayload payload) {
    scannedDevice = payload;
    onChange();
  }

  Future<void> connectWallet(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    _set(PairDeviceStep.connectingWallet);
    try {
      await walletConnect.init(context);
      await walletConnect.openConnectModal();
      connectedAddress = walletConnect.connectedAddress;
      _set(PairDeviceStep.form);
    } catch (e) {
      errorMessage = e.toString();
      _set(PairDeviceStep.form);
    } finally {
      _busy = false;
    }
  }

  Future<void> pairDevice({String? labelOverride}) async {
    if (_busy) return;
    final device = scannedDevice;
    if (device == null) return;
    _busy = true;
    errorMessage = null;
    try {
      final devicePubKey = EthereumAddress.fromHex(device.pubKey);
      controller ??=
          (await blockchain.getIdentityByUsername(username))?.controller;
      final smartAccount = controller;
      if (smartAccount == null) {
        throw Exception('Could not resolve the smart account controller.');
      }

      final salt = randomBytes32();
      final commitment = blockchain.buildDeviceCommitment(
        devicePubKey: devicePubKey,
        salt: salt,
        smartAccount: smartAccount,
      );

      _set(PairDeviceStep.committing);
      final commitExecuteCalldata = blockchain.buildExecuteCalldata(
        dest:
            EthereumAddress.fromHex(BlockchainService.deviceRegistryAddress),
        value: BigInt.zero,
        func: blockchain.buildCommitDeviceCalldata(commitment),
      );
      final commitTxHash = await walletConnect.sendTransaction(
        to: smartAccount.hex,
        data: bytesToHex(commitExecuteCalldata, include0x: true),
      );
      final commitOk = await _waitForReceipt(commitTxHash);
      if (!commitOk) {
        throw Exception('commitDevice transaction reverted on-chain.');
      }

      // Best-effort: cifra a vault key local pra chave pública do device
      // novo, se disponível — nunca aborta o pareamento por causa disso
      // (mesmo tratamento silencioso de PairDevice.tsx:85-98 no Desktop).
      var encryptedVaultKey = Uint8List(0);
      if (device.encryptionKey != null && device.encryptionKey!.isNotEmpty) {
        try {
          final vaultKey = await vaultKeyService.deriveVaultKey();
          encryptedVaultKey =
              await ecies.encrypt(vaultKey, device.encryptionKey!);
        } catch (_) {
          encryptedVaultKey = Uint8List(0);
        }
      }

      final label = (labelOverride != null && labelOverride.trim().isNotEmpty)
          ? labelOverride.trim()
          : device.label;
      final revealCalldata = blockchain.buildExecuteBatchCalldata(
        dest: [
          EthereumAddress.fromHex(BlockchainService.deviceRegistryAddress),
          smartAccount,
        ],
        value: [BigInt.zero, BigInt.zero],
        func: [
          blockchain.buildRegisterDeviceCalldata(
            devicePubKey: devicePubKey,
            label: label,
            salt: salt,
            encryptedVaultKey: encryptedVaultKey,
          ),
          blockchain.buildAddDeviceCalldata(devicePubKey),
        ],
      );

      _set(PairDeviceStep.waitingReveal);
      await Future.delayed(const Duration(seconds: 5));

      _set(PairDeviceStep.revealing);
      var revealOk = await _sendReveal(smartAccount, revealCalldata);
      if (!revealOk) {
        // Provável RevealTooEarly (block.number ainda não avançou o
        // suficiente) — 1 retentativa automática com folga extra antes de
        // desistir, evita o usuário precisar refazer o commit do zero.
        await Future.delayed(const Duration(seconds: 3));
        revealOk = await _sendReveal(smartAccount, revealCalldata);
      }
      if (!revealOk) {
        throw Exception(
            'registerDevice/addDevice transaction reverted on-chain.');
      }

      _set(PairDeviceStep.done);
    } catch (e) {
      errorMessage = e.toString();
      _set(PairDeviceStep.form);
    } finally {
      _busy = false;
    }
  }

  Future<bool> _sendReveal(
      EthereumAddress smartAccount, Uint8List calldata) async {
    final txHash = await walletConnect.sendTransaction(
      to: smartAccount.hex,
      data: bytesToHex(calldata, include0x: true),
    );
    return _waitForReceipt(txHash);
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

class PairDeviceScreen extends StatefulWidget {
  final String username;
  // Injetável para testes — em produção usa o default.
  final PairDeviceFlow? flow;

  const PairDeviceScreen({super.key, required this.username, this.flow});

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  late final PairDeviceFlow _flow;
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _flow = widget.flow ??
        PairDeviceFlow(
          username: widget.username,
          onChange: () {
            if (mounted) setState(() {});
          },
        );
  }

  @override
  void dispose() {
    _flow.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<ScannedDevicePayload>(
      MaterialPageRoute(
        builder: (_) => ScanScreen<ScannedDevicePayload>(
          title: context.l10n.pairDeviceScreenTitle,
          parse: ScannedDevicePayload.tryParse,
          invalidMessage: context.l10n.pairDeviceScreenInvalidQrMessage,
        ),
      ),
    );
    if (payload == null) return;
    _labelController.text = payload.label;
    _flow.setScannedDevice(payload);
  }

  Future<void> _handlePair() async {
    await _flow.pairDevice(labelOverride: _labelController.text);
    if (!mounted) return;
    if (_flow.step == PairDeviceStep.done && _flow.errorMessage == null) {
      Navigator.of(context).pop(true);
    }
  }

  String _stepLabel(BuildContext context, PairDeviceStep step) {
    switch (step) {
      case PairDeviceStep.form:
        return '';
      case PairDeviceStep.connectingWallet:
        return context.l10n.pairDeviceScreenStepConnecting;
      case PairDeviceStep.committing:
        return context.l10n.pairDeviceScreenStepCommitting;
      case PairDeviceStep.waitingReveal:
        return context.l10n.pairDeviceScreenStepWaitingReveal;
      case PairDeviceStep.revealing:
        return context.l10n.pairDeviceScreenStepRevealing;
      case PairDeviceStep.done:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pairDeviceScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _flow.step == PairDeviceStep.done
            ? _buildDoneUI(context)
            : _buildFormUI(context),
      ),
    );
  }

  Widget _buildFormUI(BuildContext context) {
    final busy = _flow.isBusy;
    final connected = _flow.connectedAddress != null;
    final scanned = _flow.scannedDevice;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!connected) ...[
            ElevatedButton.icon(
              onPressed: busy ? null : () => _flow.connectWallet(context),
              icon: const Icon(Icons.account_balance_wallet),
              label: Text(context.l10n.pairDeviceScreenConnectWalletButton),
            ),
          ] else if (scanned == null) ...[
            Text(
              context.l10n.pairDeviceScreenConnectedAddressLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _flow.connectedAddress!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: busy ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(context.l10n.pairDeviceScreenScanButton),
            ),
          ] else ...[
            Text(
              context.l10n.pairDeviceScreenConfirmTitle,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.pairDeviceScreenConnectedAddressLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              scanned.pubKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _labelController,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: context.l10n.pairDeviceScreenLabelField,
              ),
            ),
            const SizedBox(height: 24),
            if (busy) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stepLabel(context, _flow.step)),
            ] else
              ElevatedButton(
                onPressed: _handlePair,
                child: Text(context.l10n.pairDeviceScreenPairButton),
              ),
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
            context.l10n.pairDeviceScreenSuccessMessage,
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

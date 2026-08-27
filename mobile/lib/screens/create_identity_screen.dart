import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/local_storage_service.dart';
import '../services/vault_key_service.dart';
import '../services/wallet_connect_service.dart';
import '../theme.dart';
import '../utils/ecdsa_signature.dart';
import '../utils/eth_amount.dart';
import '../utils/identity_consent_hash.dart';

enum UsernameAvailability { available, taken, alreadyHasIdentity, error }

enum CreateIdentityStep {
  form,
  connectingWallet,
  checkingAvailability,
  predictingAddress,
  signingConsent,
  creatingIdentity,
  deployingAccount,
  fundingAccount,
  done,
}

/// Máquina de estados do fluxo de criar identidade 100% pelo Mobile (P68,
/// fatia 1) — espelha a sequência de `CreateIdentity.tsx` no Desktop:
/// conectar wallet -> prever endereço da smart account -> assinar
/// consentimento -> createIdentity -> createAccount -> financiar ->
/// (opcional) derivar a vault key.
///
/// Classe pura, sem dependência do widget — testável sem pump/build,
/// mesmo princípio de `sign_eip191_hash_raw`/`sign_personal_message_raw` no
/// Desktop (Rust): isolar a lógica de negócio da camada de I/O ao redor.
///
/// Guarda síncrona de disparo duplo: `_busy` é checado e setado antes de
/// qualquer `await`, então uma 2ª chamada concorrente (ex: duplo toque num
/// botão) sempre desiste cedo — mesmo achado real documentado em
/// `CreateIdentity.tsx:156-165` no Desktop (useWriteContract não vira
/// `isPending` a tempo de bloquear um 2º disparo síncrono), que aqui importa
/// mais, não menos: um pedido WalletConnect é uma ida-e-volta assíncrona pra
/// outro app, mais lenta e mais fácil de disparar 2x.
class CreateIdentityFlow {
  final WalletConnectService walletConnect;
  final BlockchainService blockchain;
  final VaultKeyService vaultKeyService;
  final LocalStorageService storage;
  final void Function() onChange;

  CreateIdentityFlow({
    required this.onChange,
    WalletConnectService? walletConnect,
    BlockchainService? blockchain,
    VaultKeyService? vaultKeyService,
    LocalStorageService? storage,
  })  : walletConnect = walletConnect ?? WalletConnectService(),
        blockchain = blockchain ?? BlockchainService(),
        vaultKeyService = vaultKeyService ?? VaultKeyService(),
        storage = storage ?? LocalStorageService();

  bool _busy = false;
  bool get isBusy => _busy;

  CreateIdentityStep step = CreateIdentityStep.form;
  String? errorMessage;
  String? connectedAddress;
  EthereumAddress? predictedAddress;
  BigInt? identityId;
  bool vaultKeyDerived = false;

  void _set(CreateIdentityStep newStep) {
    step = newStep;
    onChange();
  }

  Future<void> connectWallet(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    _set(CreateIdentityStep.connectingWallet);
    try {
      await walletConnect.init(context);
      await walletConnect.openConnectModal();
      connectedAddress = walletConnect.connectedAddress;
      _set(CreateIdentityStep.form);
    } catch (e) {
      errorMessage = e.toString();
      _set(CreateIdentityStep.form);
    } finally {
      _busy = false;
    }
  }

  /// Confirma que o @username está livre e que esta wallet ainda não tem
  /// identidade — mesmo guard que CreateIdentity.tsx faz no Desktop antes de
  /// gastar gas. Sem BuildContext de propósito (classe pura, sem dependência
  /// de UI/l10n) — quem chama traduz o enum pro texto certo.
  Future<UsernameAvailability> checkAvailability(String username) async {
    if (_busy) return UsernameAvailability.available;
    _busy = true;
    errorMessage = null;
    _set(CreateIdentityStep.checkingAvailability);
    try {
      final owner = EthereumAddress.fromHex(connectedAddress!);
      final controller = await blockchain.predictSmartAccountAddress(owner);
      predictedAddress = controller;

      final existingUsername =
          await blockchain.getUsernameByController(controller);
      if (existingUsername.isNotEmpty) {
        return UsernameAvailability.alreadyHasIdentity;
      }

      final taken = await blockchain.isUsernameTaken(username);
      if (taken) {
        return UsernameAvailability.taken;
      }

      return UsernameAvailability.available;
    } catch (e) {
      errorMessage = e.toString();
      return UsernameAvailability.error;
    } finally {
      _set(CreateIdentityStep.form);
      _busy = false;
    }
  }

  /// A sequência inteira: assinar consentimento, createIdentity,
  /// createAccount, financiar. `fundingEthText` é o texto cru do campo de
  /// valor (base-10, ex: "0.001") — parseado via EtherAmount pra evitar
  /// imprecisão de ponto flutuante.
  Future<void> createIdentity({
    required String username,
    required String fundingEthText,
  }) async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    try {
      final owner = EthereumAddress.fromHex(connectedAddress!);
      final controller =
          predictedAddress ?? await blockchain.predictSmartAccountAddress(owner);
      predictedAddress = controller;

      _set(CreateIdentityStep.signingConsent);
      final consentHash = buildIdentityConsentHash(
        chainId: BlockchainService.chainId,
        identityRegistryAddress: EthereumAddress.fromHex(
            BlockchainService.identityRegistryAddress),
        username: username,
        controller: controller,
      );
      final consentSigHex = await walletConnect.personalSign(consentHash);
      final consentSig = parseSignatureHex(consentSigHex);

      _set(CreateIdentityStep.creatingIdentity);
      final createIdentityCalldata = blockchain.buildCreateIdentityCalldata(
        username: username,
        controller: controller,
        v: consentSig.v,
        r: consentSig.r,
        s: consentSig.s,
      );
      final createIdentityTxHash = await walletConnect.sendTransaction(
        to: BlockchainService.identityRegistryAddress,
        data: bytesToHex(createIdentityCalldata, include0x: true),
      );
      final createIdentityOk = await _waitForReceipt(createIdentityTxHash);
      if (!createIdentityOk) {
        throw Exception('createIdentity transaction reverted on-chain.');
      }

      _set(CreateIdentityStep.deployingAccount);
      final createAccountCalldata =
          blockchain.buildCreateAccountCalldata(owner);
      final deployAccountTxHash = await walletConnect.sendTransaction(
        to: BlockchainService.truthidAccountFactoryAddress,
        data: bytesToHex(createAccountCalldata, include0x: true),
      );
      final deployAccountOk = await _waitForReceipt(deployAccountTxHash);
      if (!deployAccountOk) {
        throw Exception('createAccount transaction reverted on-chain.');
      }

      _set(CreateIdentityStep.fundingAccount);
      final fundingWei = parseEthToWei(fundingEthText);
      if (fundingWei > BigInt.zero) {
        final fundingTxHash = await walletConnect.sendTransaction(
          to: controller.hex,
          valueWei: fundingWei,
        );
        final fundingOk = await _waitForReceipt(fundingTxHash);
        if (!fundingOk) {
          throw Exception('Funding transaction reverted on-chain.');
        }
      }

      final identity = await blockchain.getIdentityByUsername(username);
      identityId = identity?.id;
      if (identityId != null) {
        await storage.savePairedIdentity(identityId.toString());
      }

      _set(CreateIdentityStep.done);
    } catch (e) {
      errorMessage = e.toString();
      _set(CreateIdentityStep.form);
    } finally {
      _busy = false;
    }
  }

  /// Etapa opcional, separada — assina a mensagem fixa da vault key e
  /// deriva/persiste via HKDF (mesmo formato do Desktop, ver
  /// VaultKeyService.deriveAndStoreFromWalletSignature). Skippable: o
  /// usuário pode seguir sem isso e derivar depois.
  Future<void> deriveVaultKey() async {
    if (_busy) return;
    _busy = true;
    errorMessage = null;
    onChange();
    try {
      const message = 'TruthID Vault Key v1';
      final sigHex =
          await walletConnect.personalSign(Uint8List.fromList(message.codeUnits));
      final sig = parseSignatureHex(sigHex);
      await vaultKeyService.deriveAndStoreFromWalletSignature(
        r: sig.r,
        s: sig.s,
        v: sig.v,
      );
      vaultKeyDerived = true;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      _busy = false;
      onChange();
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

class CreateIdentityScreen extends StatefulWidget {
  // Injetável para testes — em produção usa o default.
  final CreateIdentityFlow? flow;

  const CreateIdentityScreen({super.key, this.flow});

  @override
  State<CreateIdentityScreen> createState() => _CreateIdentityScreenState();
}

class _CreateIdentityScreenState extends State<CreateIdentityScreen> {
  late final CreateIdentityFlow _flow;
  final _usernameController = TextEditingController();
  final _fundingController = TextEditingController(text: '0.001');
  String? _formError;

  @override
  void initState() {
    super.initState();
    _flow = widget.flow ?? CreateIdentityFlow(onChange: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flow.dispose();
    _usernameController.dispose();
    _fundingController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    setState(() => _formError = null);
    final availability = await _flow.checkAvailability(username);
    if (!mounted) return;
    switch (availability) {
      case UsernameAvailability.taken:
        setState(() => _formError =
            context.l10n.createIdentityScreenUsernameTakenError);
        return;
      case UsernameAvailability.alreadyHasIdentity:
        setState(() => _formError =
            context.l10n.createIdentityScreenAlreadyHasIdentityError);
        return;
      case UsernameAvailability.error:
        // flow.errorMessage já foi setado (e o widget reconstruído via
        // onChange) por checkAvailability — exibido pelo bloco de erro
        // existente no build().
        return;
      case UsernameAvailability.available:
        break;
    }

    await _flow.createIdentity(
      username: username,
      fundingEthText: _fundingController.text.trim().isEmpty
          ? '0'
          : _fundingController.text.trim(),
    );

    if (!mounted) return;
    if (_flow.step == CreateIdentityStep.done && _flow.errorMessage == null) {
      Navigator.of(context).pop(true);
    }
  }

  String _stepLabel(BuildContext context, CreateIdentityStep step) {
    switch (step) {
      case CreateIdentityStep.form:
        return '';
      case CreateIdentityStep.connectingWallet:
        return context.l10n.createIdentityScreenStepConnecting;
      case CreateIdentityStep.checkingAvailability:
        return context.l10n.createIdentityScreenStepChecking;
      case CreateIdentityStep.predictingAddress:
        return context.l10n.createIdentityScreenStepPredicting;
      case CreateIdentityStep.signingConsent:
        return context.l10n.createIdentityScreenStepSigningConsent;
      case CreateIdentityStep.creatingIdentity:
        return context.l10n.createIdentityScreenStepCreatingIdentity;
      case CreateIdentityStep.deployingAccount:
        return context.l10n.createIdentityScreenStepDeployingAccount;
      case CreateIdentityStep.fundingAccount:
        return context.l10n.createIdentityScreenStepFunding;
      case CreateIdentityStep.done:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.createIdentityScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _flow.step == CreateIdentityStep.done
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
              label: Text(context.l10n.createIdentityScreenConnectWalletButton),
            ),
          ] else ...[
            Text(
              context.l10n.createIdentityScreenConnectedAddressLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _flow.connectedAddress!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: context.l10n.createIdentityScreenUsernameLabel,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fundingController,
              enabled: !busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.l10n.createIdentityScreenFundingLabel,
              ),
            ),
            const SizedBox(height: 24),
            if (busy) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stepLabel(context, _flow.step)),
            ] else
              ElevatedButton(
                onPressed: _handleCreate,
                child: Text(context.l10n.createIdentityScreenCreateButton),
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
            context.l10n.createIdentityScreenSuccessMessage,
            style: const TextStyle(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (!_flow.vaultKeyDerived) ...[
            ElevatedButton(
              onPressed: _flow.isBusy ? null : () => _flow.deriveVaultKey(),
              child: _flow.isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.createIdentityScreenDeriveVaultKeyButton),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.createIdentityScreenSkipVaultKeyButton),
            ),
          ] else ...[
            Text(
              context.l10n.createIdentityScreenVaultKeyDerivedMessage,
              style: const TextStyle(color: AppColors.success),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.createIdentityScreenContinueButton),
            ),
          ],
        ],
      ),
    );
  }
}

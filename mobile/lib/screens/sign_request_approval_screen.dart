import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/cross_device_delivery_channel.dart';
import '../services/deep_link_delivery_channel.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/pinning_provider_service.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/result_delivery_channel.dart';
import '../services/session_creator.dart';
import '../services/vault_lan_server_service.dart';
import '../theme.dart';
import '../widgets/info_row.dart';

// Estados possíveis da tela — do QR escaneado até a entrega do resultado.
// Duas etapas extras em relação a SignMessageApprovalScreen: `loading`
// (resolver a smart account pareada antes de poder aprovar) e `executing`
// (rodar a UserOperation de verdade — bundler + polling de recibo — antes de
// entregar o resultado, já que /sign-request assina E executa, diferente do
// /sign-message que só assina).
enum _Status {
  loading,
  pending,
  executing,
  sending,
  sent,
  timeout,
  error,
}

/// Recalcula o seletor de `functionSignature` (keccak256, 4 primeiros bytes)
/// e compara contra os 4 primeiros bytes de `callData` — mesma técnica já
/// usada em blockchain_service.dart pra outros seletores, e mesma checagem
/// que `SignRequestModal.tsx` já faz no Desktop (`toFunctionSelector`) antes
/// de confiar na `functionSignature` declarada. Nunca decodifica argumentos —
/// mesma postura do lado Rust (`sign_request.rs` nunca decodifica callData),
/// e não bloqueia se não bater: a aprovação humana é o ponto de confiança
/// final, mesma decisão consciente da fatia 2b do Desktop.
bool _selectorMatches(String functionSignature, String callDataHex) {
  try {
    final selector =
        keccak256(Uint8List.fromList(utf8.encode(functionSignature)))
            .sublist(0, 4);
    final callDataBytes = hexToBytes(callDataHex);
    if (callDataBytes.length < 4) return false;
    return bytesToHex(selector) == bytesToHex(callDataBytes.sublist(0, 4));
  } catch (_) {
    return false;
  }
}

/// Tela de aprovação de `/sign-request` cross-device — mirror estrutural de
/// `SignMessageApprovalScreen`, com duas diferenças reais: (1) precisa
/// resolver a smart account da identidade pareada neste celular antes de
/// poder aprovar (o QR nunca traz `smartAccountAddress` — mesma postura de
/// `SignRequestBody` no Rust, que nem tem esse campo, e de
/// `SignRequestModal.tsx` no Desktop, que lê de `App.tsx`); (2) Approve
/// executa a UserOperation de verdade via `SessionCreator` (bundler + espera
/// de recibo) antes de entregar o resultado, em vez de só assinar.
///
/// Schema do QR v1 (`transport` ausente/`'qr'`):
///   { action: 'truthid-sign-request', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName, dest, value, callData, functionSignature }
/// Schema do deep link (`transport: 'deeplink'`, mesmo aparelho — ver
/// `DeepLinkService`): igual, menos `ephemeralPubKey` (sem cifra: não há
/// salto de rede não confiável a proteger), mais `callback` (URI do
/// esquema do app requisitante pra onde o resultado volta).
///
/// Transporte QR: dois em paralelo, mesmo padrão que sign-message já usa —
/// `RemoteSignerLanServer` (bloco de portas `48050-48054`) decide
/// `sent`/`timeout`, e um dead-drop IPFS/IPNS best-effort
/// (`IpfsPinClient.publishDeadDrop`) roda ao lado, nunca decide o status.
/// Transporte deep link: sem cifra nem LAN/dead-drop, só devolve via outro
/// deep link (`DeepLinkDeliveryChannel`).
class SignRequestApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final SessionCreator? sessionCreator;
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final BundlerConfigService? bundlerConfigService;
  final EciesService? eciesService;
  final RemoteSignerLanServer? lanServer;
  final IpfsPinClient? ipfsPinClient;
  final PinningProviderService? pinningProviderService;
  final ResultDeliveryChannel? deliveryChannel;

  const SignRequestApprovalScreen({
    super.key,
    required this.payload,
    this.sessionCreator,
    this.blockchainService,
    this.localStorageService,
    this.bundlerConfigService,
    this.eciesService,
    this.lanServer,
    this.ipfsPinClient,
    this.pinningProviderService,
    this.deliveryChannel,
  });

  @override
  State<SignRequestApprovalScreen> createState() =>
      _SignRequestApprovalScreenState();
}

class _SignRequestApprovalScreenState
    extends State<SignRequestApprovalScreen> {
  late _Status _status;
  String? _sessionId;
  String? _requesterPubKeyHex;
  Uri? _callbackUri;
  DateTime? _expiresAt;
  String? _appName;
  String? _dest;
  String? _value;
  String? _callData;
  String? _functionSignature;
  bool _selectorVerified = false;
  String? _errorMsg;
  List<String> _localIps = [];
  String? _deadDropIpnsName;
  String? _deadDropError;

  EthereumAddress? _smartAccountAddress;
  SessionCreator? _sessionCreator;
  String? _executionOutcome; // 'executed' | 'rejected' | 'failed'
  String? _userOpHash;
  String? _executionError;
  bool _responded = false; // impede duplo toque de submeter 2 UserOperations

  late final String _transport;
  late final BlockchainService _blockchain;
  late final LocalStorageService _storage;
  late final BundlerConfigService _bundlerConfigService;
  late final EciesService _ecies;
  late final RemoteSignerLanServer _lanServer;
  late final IpfsPinClient _ipfsPinClient;
  late final PinningProviderService _pinningProviderService;
  ResultDeliveryChannel? _deliveryChannel;

  // `_validatePayload` usa `context.l10n`, que só fica disponível a partir
  // de `didChangeDependencies()` (chamá-lo direto em `initState()` derruba
  // um assert do framework). Guardado por `_initialized` pra rodar só uma
  // vez, já que `didChangeDependencies()` pode re-disparar depois.
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _transport = widget.payload['transport'] as String? ?? 'qr';
    _blockchain = widget.blockchainService ?? BlockchainService();
    _storage = widget.localStorageService ?? LocalStorageService();
    _bundlerConfigService =
        widget.bundlerConfigService ?? BundlerConfigService();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();
    _ipfsPinClient = widget.ipfsPinClient ?? IpfsPinClient();
    _pinningProviderService =
        widget.pinningProviderService ?? PinningProviderService();
    _sessionCreator = widget.sessionCreator;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final invalid = _validatePayload();
    if (invalid != null) {
      _status = invalid;
      return;
    }
    _status = _Status.loading;
    _resolveSmartAccount();
  }

  ResultDeliveryChannel _resolveDeliveryChannel() {
    final injected = widget.deliveryChannel;
    if (injected != null) return injected;
    if (_transport == 'deeplink') {
      return DeepLinkDeliveryChannel(callbackBaseUri: _callbackUri!);
    }
    return CrossDeviceDeliveryChannel(
      requesterPubKeyHex: _requesterPubKeyHex!,
      ecies: _ecies,
      lanServer: _lanServer,
      ipfsPinClient: _ipfsPinClient,
      pinningProviderService: _pinningProviderService,
    );
  }

  _Status? _validatePayload() {
    final v = widget.payload['v'];
    if (v != 1) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorUnsupportedVersion;
      return _Status.error;
    }

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorMissingSessionId;
      return _Status.error;
    }

    if (_transport == 'deeplink') {
      final callback = widget.payload['callback'] as String?;
      final callbackUri = callback != null ? Uri.tryParse(callback) : null;
      if (callbackUri == null || callbackUri.scheme.isEmpty) {
        _errorMsg = context.l10n.signRequestApprovalScreenErrorInvalidCallback;
        return _Status.error;
      }
      _callbackUri = callbackUri;
    } else {
      final ephemeralPubKey = widget.payload['ephemeralPubKey'] as String?;
      if (ephemeralPubKey == null || ephemeralPubKey.isEmpty) {
        _errorMsg =
            context.l10n.signRequestApprovalScreenErrorMissingEphemeralPubKey;
        return _Status.error;
      }
      _requesterPubKeyHex = ephemeralPubKey;
    }

    final expiresAtMs = widget.payload['expiresAt'];
    if (expiresAtMs is! int) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorMissingExpiresAt;
      return _Status.error;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorExpired;
      return _Status.error;
    }

    final appName = (widget.payload['appName'] as String?)?.trim() ?? '';
    if (appName.isEmpty) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorMissingAppName;
      return _Status.error;
    }

    final dest = widget.payload['dest'] as String?;
    if (dest == null || dest.isEmpty) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorMissingDest;
      return _Status.error;
    }

    final callData = widget.payload['callData'] as String?;
    if (callData == null || callData.isEmpty) {
      _errorMsg = context.l10n.signRequestApprovalScreenErrorMissingCallData;
      return _Status.error;
    }

    final functionSignature = widget.payload['functionSignature'] as String?;
    if (functionSignature == null || functionSignature.isEmpty) {
      _errorMsg =
          context.l10n.signRequestApprovalScreenErrorMissingFunctionSignature;
      return _Status.error;
    }

    // "value" tem o mesmo default "0" que SignRequestBody tem do lado Rust
    // (`#[serde(default = "default_value")]`).
    final value = (widget.payload['value'] as String?) ?? '0';

    _sessionId = sessionId;
    _expiresAt = expiresAt;
    _appName = appName;
    _dest = dest;
    _value = value.isEmpty ? '0' : value;
    _callData = callData;
    _functionSignature = functionSignature;
    _selectorVerified = _selectorMatches(functionSignature, callData);
    return null;
  }

  Future<void> _resolveSmartAccount() async {
    final identityId = await _storage.getPairedIdentityId();
    if (identityId == null) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = context.l10n.signRequestApprovalScreenErrorNotPaired;
      });
      return;
    }

    // Achado real (Sessão 135, ultrareview): identityId persistido mas
    // username nunca resolvido é um estado real e alcançável (mesmo bug já
    // corrigido em wallet_screen.dart/vault_edit_approval_screen.dart) —
    // reportar "não pareado" aqui enganava o usuário a re-parear em vez de
    // só esperar o on-chain resolver.
    final username = await resolvePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
    );
    if (username == null) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg =
            context.l10n.signRequestApprovalScreenErrorResolvingIdentity;
      });
      return;
    }

    try {
      final identity = await _blockchain.getIdentityByUsername(username);
      if (identity == null) {
        if (!mounted) return;
        setState(() {
          _status = _Status.error;
          _errorMsg = context
              .l10n.signRequestApprovalScreenErrorSmartAccountUnresolved;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _smartAccountAddress = identity.controller;
        _status = _Status.pending;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg =
            context.l10n.signRequestApprovalScreenErrorSmartAccountFailed('$e');
      });
    }
  }

  Future<void> _ensureSessionCreator() async {
    if (_sessionCreator != null) return;
    final bundlerConfig = await _bundlerConfigService.getConfig();
    _sessionCreator = SessionCreator(
      bundlerClient: PimlicoBundlerClient(
        bundlerUrl: pimlicoBundlerUrl(
          apiKey: bundlerConfig.apiKey,
          network: bundlerConfig.network,
        ),
      ),
    );
  }

  Future<void> _approve() async {
    if (_responded) return;
    _responded = true;
    setState(() => _status = _Status.executing);

    try {
      await _ensureSessionCreator();
      final result = await _sessionCreator!.executeArbitraryCall(
        smartAccountAddress: _smartAccountAddress!,
        dest: EthereumAddress.fromHex(_dest!),
        value: BigInt.parse(_value!),
        innerCallData: hexToBytes(_callData!),
      );
      _executionOutcome = 'executed';
      _userOpHash = result.userOpHash;
      await _deliver({
        'status': 'executed',
        'userOpHash': result.userOpHash,
        'transactionHash': result.transactionHash,
      });
    } catch (e) {
      _executionOutcome = 'failed';
      _executionError = '$e';
      await _deliver({'status': 'failed', 'error': '$e'});
    }
  }

  Future<void> _reject() async {
    if (_responded) return;
    _responded = true;
    _executionOutcome = 'rejected';
    await _deliver({'status': 'rejected'});
  }

  Future<void> _deliver(Map<String, dynamic> result) async {
    setState(() {
      _status = _Status.sending;
      _deadDropIpnsName = null;
      _deadDropError = null;
    });

    // Só faz sentido fora do caminho deep link — sem rede envolvida, não há
    // IP local nenhum pra mostrar.
    if (_transport != 'deeplink') {
      unawaited(
        VaultLanServerService.getLocalIpAddresses()
            .then((ips) => setState(() => _localIps = ips))
            .catchError((_) => <String>[]),
      );
    }

    try {
      final expiresAt = _expiresAt!;
      if (expiresAt.isBefore(DateTime.now())) {
        setState(() {
          _status = _Status.error;
          _errorMsg = context
              .l10n.signRequestApprovalScreenErrorSessionExpiredResponding;
        });
        return;
      }

      _deliveryChannel ??= _resolveDeliveryChannel();
      final delivered = await _deliveryChannel!.deliver(
        result: result,
        sessionId: _sessionId!,
        expiresAt: expiresAt,
      );

      if (!mounted) return;
      setState(() {
        _status = delivered.outcome == DeliveryOutcome.sent
            ? _Status.sent
            : _Status.timeout;
        _deadDropIpnsName = delivered.deadDropIpnsName;
        _deadDropError = delivered.deadDropError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg =
            context.l10n.signRequestApprovalScreenErrorRespondFailed('$e');
      });
    }
  }

  String _resultSummary(BuildContext context) {
    switch (_executionOutcome) {
      case 'executed':
        return context.l10n
            .signRequestApprovalScreenResultExecuted(_userOpHash ?? '');
      case 'failed':
        return context.l10n
            .signRequestApprovalScreenResultFailed(_executionError ?? '');
      case 'rejected':
      default:
        return context.l10n.signRequestApprovalScreenResultRejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.signRequestApprovalScreenTitle)),
      body: switch (_status) {
        _Status.loading => _buildLoadingUI(),
        _Status.pending => _buildPendingUI(),
        _Status.executing => _buildExecutingUI(),
        _Status.sending => _buildSendingUI(),
        _Status.sent => _buildSentUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildLoadingUI() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildPendingUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.bolt_outlined, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n
                  .signRequestApprovalScreenPendingHeading(_appName ?? ''),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenGasNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            InfoRow(
              label: context.l10n.signRequestApprovalScreenDestinationLabel,
              value: _dest ?? '',
            ),
            InfoRow(
              label: context.l10n.signRequestApprovalScreenValueLabel,
              value: _value ?? '',
            ),
            InfoRow(
              label: _selectorVerified
                  ? context.l10n.signRequestApprovalScreenFunctionVerifiedLabel
                  : context
                      .l10n.signRequestApprovalScreenFunctionUnverifiedLabel,
              value: _functionSignature ?? '',
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenRawCallDataLabel,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              _callData ?? '',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(context.l10n.signRequestApprovalScreenApproveButton,
                  style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _reject,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(context.l10n.signRequestApprovalScreenRejectButton,
                  style: const TextStyle(fontSize: 18)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutingUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              context.l10n.signRequestApprovalScreenExecutingHeading,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenExecutingBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendingUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            Text(
              context.l10n.signRequestApprovalScreenWaitingHeading,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenWifiHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (_localIps.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                context.l10n.signRequestApprovalScreenManualIpHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              ..._localIps.map(
                (ip) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    ip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSentUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.signRequestApprovalScreenSentHeading,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenSentBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              _resultSummary(context),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (_deadDropIpnsName != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.signRequestApprovalScreenDeadDropPublished,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ] else if (_deadDropError != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.signRequestApprovalScreenDeadDropUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signRequestApprovalScreenDoneButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 72, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              context.l10n.signRequestApprovalScreenTimeoutHeading,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signRequestApprovalScreenTimeoutBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signRequestApprovalScreenBackButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? context.l10n.signRequestApprovalScreenGenericError,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signRequestApprovalScreenBackButton),
            ),
          ],
        ),
      ),
    );
  }
}

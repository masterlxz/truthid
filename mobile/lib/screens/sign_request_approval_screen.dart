import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/local_storage_service.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/pinning_provider_service.dart';
import '../services/remote_signer_lan_server.dart';
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
/// Schema do QR v1:
///   { action: 'truthid-sign-request', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName, dest, value, callData, functionSignature }
///
/// Transporte: dois em paralelo, mesmo padrão que sign-message já usa —
/// `RemoteSignerLanServer` (bloco de portas `48050-48054`) decide
/// `sent`/`timeout`, e um dead-drop IPFS/IPNS best-effort
/// (`IpfsPinClient.publishDeadDrop`) roda ao lado, nunca decide o status.
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

  late final BlockchainService _blockchain;
  late final LocalStorageService _storage;
  late final BundlerConfigService _bundlerConfigService;
  late final EciesService _ecies;
  late final RemoteSignerLanServer _lanServer;
  late final IpfsPinClient _ipfsPinClient;
  late final PinningProviderService _pinningProviderService;

  @override
  void initState() {
    super.initState();
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

    final invalid = _validatePayload();
    if (invalid != null) {
      _status = invalid;
      return;
    }
    _status = _Status.loading;
    _resolveSmartAccount();
  }

  _Status? _validatePayload() {
    final v = widget.payload['v'];
    if (v != 1) {
      _errorMsg = 'Invalid QR: unsupported schema version.';
      return _Status.error;
    }

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMsg = 'Invalid QR: missing sessionId.';
      return _Status.error;
    }

    final ephemeralPubKey = widget.payload['ephemeralPubKey'] as String?;
    if (ephemeralPubKey == null || ephemeralPubKey.isEmpty) {
      _errorMsg = 'Invalid QR: missing ephemeralPubKey.';
      return _Status.error;
    }

    final expiresAtMs = widget.payload['expiresAt'];
    if (expiresAtMs is! int) {
      _errorMsg = 'Invalid QR: missing expiresAt.';
      return _Status.error;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      _errorMsg = 'This QR code has expired — go back to the app and scan a '
          'fresh one.';
      return _Status.error;
    }

    final appName = (widget.payload['appName'] as String?)?.trim() ?? '';
    if (appName.isEmpty) {
      _errorMsg = 'Invalid QR: missing appName.';
      return _Status.error;
    }

    final dest = widget.payload['dest'] as String?;
    if (dest == null || dest.isEmpty) {
      _errorMsg = 'Invalid QR: missing dest.';
      return _Status.error;
    }

    final callData = widget.payload['callData'] as String?;
    if (callData == null || callData.isEmpty) {
      _errorMsg = 'Invalid QR: missing callData.';
      return _Status.error;
    }

    final functionSignature = widget.payload['functionSignature'] as String?;
    if (functionSignature == null || functionSignature.isEmpty) {
      _errorMsg = 'Invalid QR: missing functionSignature.';
      return _Status.error;
    }

    // "value" tem o mesmo default "0" que SignRequestBody tem do lado Rust
    // (`#[serde(default = "default_value")]`).
    final value = (widget.payload['value'] as String?) ?? '0';

    _sessionId = sessionId;
    _requesterPubKeyHex = ephemeralPubKey;
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
    final username = await _storage.getPairedUsername();
    if (identityId == null || username == null) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = "This phone isn't paired with a TruthID identity yet.";
      });
      return;
    }

    try {
      final identity = await _blockchain.getIdentityByUsername(username);
      if (identity == null) {
        if (!mounted) return;
        setState(() {
          _status = _Status.error;
          _errorMsg = 'Could not resolve your smart account — try again.';
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
        _errorMsg = 'Failed to resolve your smart account: $e';
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
    _executionOutcome = 'rejected';
    await _deliver({'status': 'rejected'});
  }

  Future<void> _deliver(Map<String, dynamic> result) async {
    setState(() {
      _status = _Status.sending;
      _deadDropIpnsName = null;
      _deadDropError = null;
    });

    unawaited(
      VaultLanServerService.getLocalIpAddresses()
          .then((ips) => setState(() => _localIps = ips))
          .catchError((_) => <String>[]),
    );

    try {
      final expiresAt = _expiresAt!;
      if (expiresAt.isBefore(DateTime.now())) {
        setState(() {
          _status = _Status.error;
          _errorMsg = 'Session expired before responding — scan the QR again.';
        });
        return;
      }

      final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(result)));
      final encryptedBlob =
          await _ecies.encrypt(plaintext, _requesterPubKeyHex!);

      // Mesma decisão travada da 13.9/sign-message: o dead-drop corre em
      // paralelo com o LAN, nunca como fallback sequencial, e nunca lança —
      // uma falha (sem provider Kubo configurado, Kubo fora do ar) não pode
      // derrubar o transporte LAN, que já funciona sozinho.
      final deadDropFuture = _publishDeadDrop(encryptedBlob);

      final served = await _lanServer.serveOnce(
        encryptedBlob: encryptedBlob,
        sessionId: _sessionId!,
        expiresAt: expiresAt,
      );
      await deadDropFuture;

      if (!mounted) return;
      setState(() => _status = served ? _Status.sent : _Status.timeout);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to respond to the app: $e';
      });
    }
  }

  Future<void> _publishDeadDrop(Uint8List encryptedBlob) async {
    try {
      final providers = await _pinningProviderService.load();
      final ipnsName = await _ipfsPinClient.publishDeadDrop(
        _sessionId!,
        encryptedBlob,
        providers,
      );
      if (!mounted) return;
      setState(() => _deadDropIpnsName = ipnsName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deadDropError = '$e');
    }
  }

  String _resultSummary() {
    switch (_executionOutcome) {
      case 'executed':
        return 'Transaction executed (UserOp ${_userOpHash ?? ''}).';
      case 'failed':
        return 'Transaction failed: ${_executionError ?? ''}';
      case 'rejected':
      default:
        return 'You rejected this request.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign & execute request')),
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
              '$_appName wants to execute a transaction',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your smart account will pay the gas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            InfoRow(label: 'Destination', value: _dest ?? ''),
            InfoRow(label: 'Value (wei)', value: _value ?? ''),
            InfoRow(
              label: _selectorVerified
                  ? 'Function (verified)'
                  : 'Function (unverified)',
              value: _functionSignature ?? '',
            ),
            const SizedBox(height: 8),
            const Text(
              'Raw call data:',
              style: TextStyle(color: AppColors.textMuted),
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
              label: const Text('Approve', style: TextStyle(fontSize: 18)),
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
              label: const Text('Reject', style: TextStyle(fontSize: 18)),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Executing transaction...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Sending to the bundler and waiting for confirmation. This can '
              'take up to a minute.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
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
            const Text(
              'Waiting for the app to connect...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure your phone and computer are on the same Wi-Fi '
              'network.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            if (_localIps.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'If the app can\'t find your phone automatically, enter this '
                'IP address manually:',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
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
            const Text(
              'Sent',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The app received your response.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              _resultSummary(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (_deadDropIpnsName != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Dead-drop backup published (IPFS/IPNS).',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ] else if (_deadDropError != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Dead-drop backup unavailable this time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
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
            const Text(
              'Nothing arrived',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The app never connected before this request expired. Make '
              'sure both devices are on the same Wi-Fi network and try '
              'again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
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
              _errorMsg ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../services/cross_device_delivery_channel.dart';
import '../services/deep_link_delivery_channel.dart';
import '../services/device_key_service.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/pinning_provider_service.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/result_delivery_channel.dart';
import '../services/vault_lan_server_service.dart';
import '../theme.dart';
import '../widgets/info_row.dart';

// Estados possíveis da tela — do QR escaneado até a entrega do resultado.
// Dois transportes correm em paralelo (mesmo padrão da 13.9): LAN
// (`RemoteSignerLanServer`, decide `sent`/`timeout`) e dead-drop IPFS/IPNS
// (`IpfsPinClient.publishDeadDrop`, best-effort, nunca decide o status).
enum _Status {
  pending,
  sending,
  sent,
  timeout,
  error,
}

/// `purpose` é um identificador curto, não texto livre — mesma regra exata
/// do lado Rust (`sign_message.rs::is_valid_purpose`), pra manter os dois
/// canais (Desktop loopback e Mobile cross-device) consistentes.
bool _isValidPurpose(String purpose) {
  if (purpose.isEmpty || purpose.length > 64) return false;
  return RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(purpose);
}

/// Tela de aprovação de `/sign-message` cross-device — um app terceiro (ex:
/// Practice Valuation) mostra um QR com o pedido inteiro (cabe fácil, é só
/// `{appName, purpose}`), o celular escaneia e entrega o resultado (assinado
/// ou rejeitado) de volta via dois transportes em paralelo: um servidor LAN
/// efêmero (`RemoteSignerLanServer`) e um dead-drop IPFS/IPNS best-effort
/// (`IpfsPinClient.publishDeadDrop`) pro caso de celular e app terceiro não
/// estarem na mesma rede — mesmo padrão que a 13.9 já validou pro Vault.
///
/// Schema do QR v1 (`transport` ausente/`'qr'`):
///   { action: 'truthid-sign-message', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName, purpose }
/// Schema do deep link (`transport: 'deeplink'`, mesmo aparelho — ver
/// `DeepLinkService`): igual, menos `ephemeralPubKey` (sem cifra: não há
/// salto de rede não confiável a proteger), mais `callback` (URI do
/// esquema do app requisitante pra onde o resultado volta).
/// A mensagem final NUNCA vem pronta do payload — é sempre reconstruída
/// aqui a partir de appName/purpose, mesmo motivo de domain separation do
/// lado Rust: um app terceiro não pode escolher a string exata que é
/// assinada.
class SignMessageApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final DeviceKeyService? deviceKeyService;
  final EciesService? eciesService;
  final RemoteSignerLanServer? lanServer;
  final IpfsPinClient? ipfsPinClient;
  final PinningProviderService? pinningProviderService;
  final ResultDeliveryChannel? deliveryChannel;

  const SignMessageApprovalScreen({
    super.key,
    required this.payload,
    this.deviceKeyService,
    this.eciesService,
    this.lanServer,
    this.ipfsPinClient,
    this.pinningProviderService,
    this.deliveryChannel,
  });

  @override
  State<SignMessageApprovalScreen> createState() =>
      _SignMessageApprovalScreenState();
}

class _SignMessageApprovalScreenState
    extends State<SignMessageApprovalScreen> {
  late _Status _status;
  String? _sessionId;
  String? _requesterPubKeyHex;
  Uri? _callbackUri;
  DateTime? _expiresAt;
  String? _appName;
  String? _purpose;
  String? _message;
  String? _errorMsg;
  List<String> _localIps = [];
  String? _deadDropIpnsName;
  String? _deadDropError;

  late final String _transport;
  late final DeviceKeyService _keyService;
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
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();
    _ipfsPinClient = widget.ipfsPinClient ?? IpfsPinClient();
    _pinningProviderService =
        widget.pinningProviderService ?? PinningProviderService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _status = _validatePayload() ?? _Status.pending;
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
      _errorMsg = context.l10n.signMessageApprovalScreenErrorUnsupportedVersion;
      return _Status.error;
    }

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMsg = context.l10n.signMessageApprovalScreenErrorMissingSessionId;
      return _Status.error;
    }

    if (_transport == 'deeplink') {
      final callback = widget.payload['callback'] as String?;
      final callbackUri = callback != null ? Uri.tryParse(callback) : null;
      if (callbackUri == null || callbackUri.scheme.isEmpty) {
        _errorMsg = context.l10n.signMessageApprovalScreenErrorInvalidCallback;
        return _Status.error;
      }
      _callbackUri = callbackUri;
    } else {
      final ephemeralPubKey = widget.payload['ephemeralPubKey'] as String?;
      if (ephemeralPubKey == null || ephemeralPubKey.isEmpty) {
        _errorMsg =
            context.l10n.signMessageApprovalScreenErrorMissingEphemeralPubKey;
        return _Status.error;
      }
      _requesterPubKeyHex = ephemeralPubKey;
    }

    final expiresAtMs = widget.payload['expiresAt'];
    if (expiresAtMs is! int) {
      _errorMsg = context.l10n.signMessageApprovalScreenErrorMissingExpiresAt;
      return _Status.error;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      _errorMsg = context.l10n.signMessageApprovalScreenErrorExpired;
      return _Status.error;
    }

    final appName = (widget.payload['appName'] as String?)?.trim() ?? '';
    if (appName.isEmpty) {
      _errorMsg = context.l10n.signMessageApprovalScreenErrorMissingAppName;
      return _Status.error;
    }

    final purpose = widget.payload['purpose'] as String? ?? '';
    if (!_isValidPurpose(purpose)) {
      _errorMsg = context.l10n.signMessageApprovalScreenErrorInvalidPurpose;
      return _Status.error;
    }

    _sessionId = sessionId;
    _expiresAt = expiresAt;
    _appName = appName;
    _purpose = purpose;
    _message = 'TruthID Message Signing: $appName:$purpose';
    return null;
  }

  Future<void> _approve() async {
    final signature = await _keyService.signChallenge(_message!);
    await _deliver({
      'status': 'signed',
      'message': _message,
      'signature': signature,
    });
  }

  Future<void> _reject() async {
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
              .l10n.signMessageApprovalScreenErrorSessionExpiredResponding;
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
            context.l10n.signMessageApprovalScreenErrorRespondFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.signMessageApprovalScreenTitle)),
      body: switch (_status) {
        _Status.pending => _buildPendingUI(),
        _Status.sending => _buildSendingUI(),
        _Status.sent => _buildSentUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildPendingUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.key_outlined, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n
                  .signMessageApprovalScreenPendingHeading(_appName ?? ''),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InfoRow(
              label: context.l10n.signMessageApprovalScreenPurposeLabel,
              value: _purpose ?? '',
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.signMessageApprovalScreenMessagePreviewLabel,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              _message ?? '',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(context.l10n.signMessageApprovalScreenApproveButton,
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
              label: Text(context.l10n.signMessageApprovalScreenRejectButton,
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
              context.l10n.signMessageApprovalScreenWaitingHeading,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signMessageApprovalScreenWifiHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (_localIps.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                context.l10n.signMessageApprovalScreenManualIpHint,
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
              context.l10n.signMessageApprovalScreenSentHeading,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signMessageApprovalScreenSentBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (_deadDropIpnsName != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.signMessageApprovalScreenDeadDropPublished,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ] else if (_deadDropError != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.signMessageApprovalScreenDeadDropUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signMessageApprovalScreenDoneButton),
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
              context.l10n.signMessageApprovalScreenTimeoutHeading,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.signMessageApprovalScreenTimeoutBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signMessageApprovalScreenBackButton),
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
              _errorMsg ?? context.l10n.signMessageApprovalScreenGenericError,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.signMessageApprovalScreenBackButton),
            ),
          ],
        ),
      ),
    );
  }
}

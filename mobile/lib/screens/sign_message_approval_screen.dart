import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/device_key_service.dart';
import '../services/ecies_service.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/vault_lan_server_service.dart';
import '../theme.dart';
import '../widgets/info_row.dart';

// Estados possíveis da tela — do QR escaneado até a entrega do resultado via
// LAN pro app terceiro. Só transporte LAN nesta fatia (dead-drop IPFS/IPNS
// fica pra uma fatia futura, mesma sequência que a 13.9 já seguiu).
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
/// ou rejeitado) de volta via um servidor LAN efêmero (`RemoteSignerLanServer`).
///
/// Schema do QR v1:
///   { action: 'truthid-sign-message', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName, purpose }
/// A mensagem final NUNCA vem pronta do QR — é sempre reconstruída aqui a
/// partir de appName/purpose, mesmo motivo de domain separation do lado
/// Rust: um app terceiro não pode escolher a string exata que é assinada.
class SignMessageApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final DeviceKeyService? deviceKeyService;
  final EciesService? eciesService;
  final RemoteSignerLanServer? lanServer;

  const SignMessageApprovalScreen({
    super.key,
    required this.payload,
    this.deviceKeyService,
    this.eciesService,
    this.lanServer,
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
  DateTime? _expiresAt;
  String? _appName;
  String? _purpose;
  String? _message;
  String? _errorMsg;
  List<String> _localIps = [];

  late final DeviceKeyService _keyService;
  late final EciesService _ecies;
  late final RemoteSignerLanServer _lanServer;

  @override
  void initState() {
    super.initState();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();

    _status = _validatePayload() ?? _Status.pending;
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

    final purpose = widget.payload['purpose'] as String? ?? '';
    if (!_isValidPurpose(purpose)) {
      _errorMsg = 'Invalid QR: purpose must be 1-64 chars of [A-Za-z0-9_.-].';
      return _Status.error;
    }

    _sessionId = sessionId;
    _requesterPubKeyHex = ephemeralPubKey;
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
    setState(() => _status = _Status.sending);

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

      final served = await _lanServer.serveOnce(
        encryptedBlob: encryptedBlob,
        sessionId: _sessionId!,
        expiresAt: expiresAt,
      );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign message request')),
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
              '$_appName wants to derive a signing key for itself',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InfoRow(label: 'Purpose', value: _purpose ?? ''),
            const SizedBox(height: 16),
            const Text(
              'Exact message that will be signed:',
              style: TextStyle(color: AppColors.textMuted),
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

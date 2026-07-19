import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/cross_device_delivery_channel.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/pin_content_cipher_service.dart';
import '../services/pinning_provider_service.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/result_delivery_channel.dart';
import '../services/vault_lan_server_service.dart';
import '../theme.dart';

// Estados da tela — diferente do irmão sign-message, aqui o "esperando rede"
// vem PRIMEIRO (fase 1, recebendo o conteúdo a pinar), não por último. Só
// depois do conteúdo chegar e ser decifrado é que a aprovação é mostrada.
enum _Status {
  receivingContent,
  awaitingApproval,
  sending,
  sent,
  timeout,
  error,
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Tela de aprovação de `/pin` cross-device — um app terceiro (ex: Practice
/// Valuation) pede pro celular pinar um conteúdo usando os providers de IPFS
/// já configurados no Vault. Diferente de `/sign-message`/`/sign-request`, o
/// celular não gera o resultado sozinho — primeiro precisa RECEBER o
/// conteúdo a pinar, que pode ser grande demais pro QR. Fluxo em 2 fases:
///
///   Fase 1 (conteúdo): o requisitante varre a LAN até achar o servidor
///   efêmero que esta tela sobe (`RemoteSignerLanServer.receiveOnce`) e
///   empurra o blob via PUT, cifrado com uma chave simétrica derivada do
///   `sessionId` (ver `pin_content_cipher_service.dart` — não dá pra usar
///   ECIES aqui, nenhuma das pontas tem a chave pública da outra nessa
///   direção).
///   Fase 2 (resultado): igual ao padrão já validado em sign-message/
///   sign-request — aprova/rejeita, entrega `{status, cid, contentHash,
///   providersOk, providersFailed}` via `CrossDeviceDeliveryChannel` (ECIES
///   contra o `ephemeralPubKey` do QR + LAN + dead-drop IPFS/IPNS).
///
/// Schema do QR v1 (só cross-device nesta rodada, sem variante deep link —
/// não faz sentido pinar via HTTP loopback dentro do mesmo device):
///   { action: 'truthid-pin', v: 1, sessionId, ephemeralPubKey, expiresAt,
///     appName }
/// Sem sistema de cota/autorização persistente por app (diferente do
/// `pin.rs` do Desktop, que é loopback e de alta frequência) — cada pedido
/// cross-device pede aprovação individual.
class PinApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final EciesService? eciesService;
  final RemoteSignerLanServer? lanServer;
  final IpfsPinClient? ipfsPinClient;
  final PinningProviderService? pinningProviderService;
  final ResultDeliveryChannel? deliveryChannel;

  const PinApprovalScreen({
    super.key,
    required this.payload,
    this.eciesService,
    this.lanServer,
    this.ipfsPinClient,
    this.pinningProviderService,
    this.deliveryChannel,
  });

  @override
  State<PinApprovalScreen> createState() => _PinApprovalScreenState();
}

class _PinApprovalScreenState extends State<PinApprovalScreen> {
  late _Status _status;
  String? _sessionId;
  String? _requesterPubKeyHex;
  DateTime? _expiresAt;
  String? _appName;
  Uint8List? _content;
  String? _errorMsg;
  List<String> _localIps = [];
  String? _deadDropIpnsName;
  String? _deadDropError;

  late final EciesService _ecies;
  late final RemoteSignerLanServer _lanServer;
  late final IpfsPinClient _ipfsPinClient;
  late final PinningProviderService _pinningProviderService;
  ResultDeliveryChannel? _deliveryChannel;

  @override
  void initState() {
    super.initState();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();
    _ipfsPinClient = widget.ipfsPinClient ?? IpfsPinClient();
    _pinningProviderService =
        widget.pinningProviderService ?? PinningProviderService();

    final validationError = _validatePayload();
    if (validationError != null) {
      _status = validationError;
      return;
    }
    _status = _Status.receivingContent;
    unawaited(_receiveContent());
  }

  ResultDeliveryChannel _resolveDeliveryChannel() {
    return widget.deliveryChannel ??
        CrossDeviceDeliveryChannel(
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

    _sessionId = sessionId;
    _requesterPubKeyHex = ephemeralPubKey;
    _expiresAt = expiresAt;
    _appName = appName;
    return null;
  }

  Future<void> _receiveContent() async {
    unawaited(
      VaultLanServerService.getLocalIpAddresses()
          .then((ips) => setState(() => _localIps = ips))
          .catchError((_) => <String>[]),
    );

    final encrypted = await _lanServer.receiveOnce(
      sessionId: _sessionId!,
      expiresAt: _expiresAt!,
    );
    if (!mounted) return;

    if (encrypted == null) {
      setState(() => _status = _Status.timeout);
      return;
    }

    try {
      final key = derivePinContentKey(_sessionId!);
      final content = await decryptPinContent(encrypted, key);
      if (!mounted) return;
      setState(() {
        _content = content;
        _status = _Status.awaitingApproval;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to decrypt the received content: $e';
      });
    }
  }

  Future<void> _approve() async {
    try {
      final providers = await _pinningProviderService.load();
      if (providers.isEmpty) {
        await _deliver({
          'status': 'failed',
          'error': 'no pinning provider configured — set one up in '
              'Vault > Pinning providers first',
        });
        return;
      }
      final result = await _ipfsPinClient.pinVault(_content!, providers);
      await _deliver({
        'status': 'pinned',
        'cid': result.cid,
        'contentHash': result.contentHash,
        'providersOk': result.providersOk,
        'providersFailed': result.providersFailed,
      });
    } catch (e) {
      await _deliver({'status': 'failed', 'error': '$e'});
    }
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

    try {
      final expiresAt = _expiresAt!;
      if (expiresAt.isBefore(DateTime.now())) {
        setState(() {
          _status = _Status.error;
          _errorMsg = 'Session expired before responding — scan the QR again.';
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
        _errorMsg = 'Failed to respond to the app: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin content request')),
      body: switch (_status) {
        _Status.receivingContent => _buildReceivingUI(),
        _Status.awaitingApproval => _buildApprovalUI(),
        _Status.sending => _buildSendingUI(),
        _Status.sent => _buildSentUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildReceivingUI() {
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
              '${_appName ?? 'An app'} wants to send content to pin...',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildApprovalUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.cloud_upload_outlined,
                size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              '$_appName wants to pin content to your IPFS providers',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Size: ${_formatBytes(_content?.length ?? 0)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
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
    return const Center(child: CircularProgressIndicator());
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

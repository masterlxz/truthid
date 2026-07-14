import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/local_storage_service.dart';
import '../services/pinning_provider_service.dart';
import '../services/vault_lan_server_service.dart';
import '../services/vault_repository.dart';
import '../services/vault_sync_service.dart';
import '../theme.dart';
import '../widgets/info_row.dart';

// Estados possíveis da tela — do QR escaneado até o envio de verdade pra
// extensão. 13.9, fatia 1 (LAN) e fatia 2a (dead-drop IPFS/IPNS, só o lado
// Mobile publica — a extensão ainda não consome isso, ver fatia 2b) rodam
// em paralelo a partir do mesmo botão "Send to extension".
enum _Status {
  info,
  selectingProfile,
  loadingMatches,
  showingMatches,
  sending,
  sent,
  timeout,
  error,
}

// Tela de "perfil pra scan da extensão" (13.8) + envio real via LAN (13.9,
// fatia 1). Schema do QR v1:
//   { action: 'truthid-vault-session', v: 1, sessionId, ephemeralPubKey, expiresAt }
// `sessionId` funciona como path HTTP e como bearer token — não há campo
// separado de "discoveryToken". `expiresAt` é timestamp absoluto (unix ms),
// evita ambiguidade de clock-skew entre os dois aparelhos.
class VaultSessionScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final BlockchainService? blockchainService;
  final VaultSyncService? vaultSyncService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final EciesService? eciesService;
  final VaultLanServerService? lanServerService;
  final IpfsPinClient? ipfsPinClient;
  final PinningProviderService? pinningProviderService;

  const VaultSessionScreen({
    super.key,
    required this.payload,
    this.blockchainService,
    this.vaultSyncService,
    this.localStorageService,
    this.deviceKeyService,
    this.eciesService,
    this.lanServerService,
    this.ipfsPinClient,
    this.pinningProviderService,
  });

  @override
  State<VaultSessionScreen> createState() => _VaultSessionScreenState();
}

class _VaultSessionScreenState extends State<VaultSessionScreen> {
  late _Status _status;
  String? _sessionId;
  String? _extensionPubKeyHex;
  DateTime? _expiresAt;
  String? _errorMsg;
  String? _selectedProfile;
  List<VaultEntry> _matchingEntries = [];
  VaultSyncStatus? _syncStatus;
  VaultSyncOutcome? _outcome;
  List<String> _localIps = [];
  String? _deadDropIpnsName;
  String? _deadDropError;

  late final BlockchainService _blockchain;
  late final VaultSyncService _syncService;
  late final LocalStorageService _storage;
  late final DeviceKeyService _keyService;
  late final EciesService _ecies;
  late final VaultLanServerService _lanServer;
  late final IpfsPinClient _ipfsPinClient;
  late final PinningProviderService _pinningProviderService;

  @override
  void initState() {
    super.initState();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _syncService = widget.vaultSyncService ??
        VaultSyncService(blockchainService: _blockchain);
    _storage = widget.localStorageService ?? LocalStorageService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServerService ?? VaultLanServerService();
    _ipfsPinClient = widget.ipfsPinClient ?? IpfsPinClient();
    _pinningProviderService =
        widget.pinningProviderService ?? PinningProviderService();

    _status = _validatePayload() ?? _Status.info;
  }

  // Valida o schema v1 do QR — sessionId, ephemeralPubKey e expiresAt são
  // todos obrigatórios; um QR já expirado (ex: foto velha de tela) é
  // rejeitado aqui, antes de gastar tempo sincronizando o vault.
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
      _errorMsg = 'This QR code has expired — go back to the extension and '
          'scan a fresh one.';
      return _Status.error;
    }

    _sessionId = sessionId;
    _extensionPubKeyHex = ephemeralPubKey;
    _expiresAt = expiresAt;
    return null;
  }

  // Sincroniza o vault (uma vez) pra saber a lista real de perfis do usuário
  // antes de mostrar o picker — os perfis fixos hardcoded foram removidos
  // (ver PROJECT_STATE.md, Sessão 97). A escolha do perfil em si (abaixo) só
  // filtra o resultado já sincronizado, sem precisar sincronizar de novo.
  //
  // Também dispara aqui (não só na hora de enviar) uma leitura das interfaces
  // de rede — no iOS isso é o que aciona o diálogo do sistema de Local
  // Network Privacy; disparar cedo evita que ele apareça competindo com o
  // timeout do TTL bem no meio do envio (ver PROJECT_STATE.md, 13.9).
  Future<void> _loadProfiles() async {
    setState(() => _status = _Status.loadingMatches);

    unawaited(
      VaultLanServerService.getLocalIpAddresses()
          .then((ips) => _localIps = ips)
          .catchError((_) => <String>[]),
    );

    final address = await _keyService.getDeviceAddress();
    var identityId = await _storage.getPairedIdentityId();
    final device = await _blockchain.getDevice(address);
    if (device != null && !device.revoked) {
      identityId ??= device.identityId.toString();
    }

    if (identityId == null) {
      if (mounted) {
        setState(() {
          _outcome = null;
          _status = _Status.selectingProfile;
        });
      }
      return;
    }

    final outcome = await _syncService.sync(BigInt.parse(identityId));
    if (mounted) {
      setState(() {
        _outcome = outcome;
        _status = _Status.selectingProfile;
      });
    }
  }

  void _selectProfile(String profile) {
    final matches = _outcome?.entries
            .where((e) => e.profiles.contains(profile))
            .toList() ??
        const <VaultEntry>[];
    setState(() {
      _selectedProfile = profile;
      _matchingEntries = matches;
      _syncStatus = _outcome?.status;
      _status = _Status.showingMatches;
    });
  }

  Future<void> _sendToExtension() async {
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
          _errorMsg = 'Session expired before sending — scan the QR again.';
        });
        return;
      }

      final plaintext = Uint8List.fromList(
        utf8.encode(
          jsonEncode(_matchingEntries.map((e) => e.toJson()).toList()),
        ),
      );
      final encryptedBlob =
          await _ecies.encrypt(plaintext, _extensionPubKeyHex!);

      // Dispara os dois transportes em paralelo (decisão travada da 13.9:
      // dead-drop nunca é fallback sequencial, sempre corre junto do LAN,
      // pra esconder a latência de propagação do IPNS atrás do tempo que o
      // usuário já ia esperar de qualquer forma). O dead-drop nunca lança —
      // é best-effort, isolado do try/catch que cobre o caminho de LAN.
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
        _errorMsg = 'Failed to send to the extension: $e';
      });
    }
  }

  // 13.9, fatia 2a: publica o blob cifrado num nome IPNS que a extensão vai
  // aprender a recalcular sozinha numa fatia futura (2b) — aqui só o lado
  // Mobile existe, não há consumidor ainda. Nunca lança: uma falha (sem
  // provider Kubo configurado, Kubo fora do ar) não pode derrubar o
  // transporte LAN, que já funciona sozinho.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extension session')),
      body: switch (_status) {
        _Status.info => _buildInfoUI(),
        _Status.selectingProfile => _buildProfilePickerUI(),
        _Status.loadingMatches => _buildLoadingUI(),
        _Status.showingMatches => _buildMatchesUI(),
        _Status.sending => _buildSendingUI(),
        _Status.sent => _buildSentUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildInfoUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.extension_outlined,
                size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              'Browser extension scan',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'A browser extension wants to receive part of your vault.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 32),
            InfoRow(label: 'Session', value: _sessionId!),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loadProfiles,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePickerUI() {
    final profileNames = _outcome?.profileNames ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Which profile should be shared?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Only entries tagged with this profile will be considered.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          if (profileNames.isEmpty)
            const Text(
              'No profiles created yet — create one from the Desktop app '
              'and sync again.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            ...profileNames.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => _selectProfile(p),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(p),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingUI() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildMatchesUI() {
    final offline = _syncStatus == VaultSyncStatus.offlineUsingCache;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            InfoRow(label: 'Profile', value: _selectedProfile ?? ''),
            const SizedBox(height: 8),
            InfoRow(label: 'Matching entries', value: '${_matchingEntries.length}'),
            if (offline) ...[
              const SizedBox(height: 16),
              const Text(
                'Offline — showing entries from your last sync.',
                style: TextStyle(color: AppColors.info),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _sendToExtension,
              child: const Text('Send to extension'),
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
              'Waiting for your browser to connect...',
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
                'If your browser can\'t find your phone automatically, enter '
                'this IP address manually:',
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
              'Your browser extension received the vault entries.',
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
              'Your browser extension never connected before this session '
              'expired. Make sure both devices are on the same Wi-Fi '
              'network and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _sendToExtension,
              child: const Text('Try again'),
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

import 'package:flutter/material.dart';

import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/vault_sync_service.dart';
import '../theme.dart';
import '../widgets/info_row.dart';

// Estados possíveis da tela — do QR escaneado até o aviso final. A entrega
// real pra extensão (transporte P2P) é escopo da 13.9; esta tela só prepara
// o terreno (scan → escolher perfil → ver quantas entradas bateriam).
enum _Status {
  info,
  selectingProfile,
  loadingMatches,
  showingMatches,
  unavailable,
  error,
}

// Tela de "perfil pra scan da extensão" (13.8). Payload do QR provisório —
// { action: 'truthid-vault-session', sessionId } — o protocolo real (o que a
// extensão de fato precisa trocar) é escopo da 13.9, não inventado aqui.
class VaultSessionScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final BlockchainService? blockchainService;
  final VaultSyncService? vaultSyncService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;

  const VaultSessionScreen({
    super.key,
    required this.payload,
    this.blockchainService,
    this.vaultSyncService,
    this.localStorageService,
    this.deviceKeyService,
  });

  @override
  State<VaultSessionScreen> createState() => _VaultSessionScreenState();
}

class _VaultSessionScreenState extends State<VaultSessionScreen> {
  late _Status _status;
  String? _sessionId;
  String? _errorMsg;
  String? _selectedProfile;
  int _matchCount = 0;
  VaultSyncStatus? _syncStatus;
  VaultSyncOutcome? _outcome;

  late final BlockchainService _blockchain;
  late final VaultSyncService _syncService;
  late final LocalStorageService _storage;
  late final DeviceKeyService _keyService;

  @override
  void initState() {
    super.initState();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _syncService = widget.vaultSyncService ??
        VaultSyncService(blockchainService: _blockchain);
    _storage = widget.localStorageService ?? LocalStorageService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _status = _Status.error;
      _errorMsg = 'Invalid QR: missing sessionId.';
      return;
    }
    _sessionId = sessionId;
    _status = _Status.info;
  }

  // Sincroniza o vault (uma vez) pra saber a lista real de perfis do usuário
  // antes de mostrar o picker — os perfis fixos hardcoded foram removidos
  // (ver PROJECT_STATE.md, Sessão 97). A escolha do perfil em si (abaixo) só
  // filtra o resultado já sincronizado, sem precisar sincronizar de novo.
  Future<void> _loadProfiles() async {
    setState(() => _status = _Status.loadingMatches);

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
    final matches =
        _outcome?.entries.where((e) => e.profiles.contains(profile)).length ??
            0;
    setState(() {
      _selectedProfile = profile;
      _matchCount = matches;
      _syncStatus = _outcome?.status;
      _status = _Status.showingMatches;
    });
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
        _Status.unavailable => _buildUnavailableUI(),
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
            InfoRow(label: 'Matching entries', value: '$_matchCount'),
            if (offline) ...[
              const SizedBox(height: 16),
              const Text(
                'Offline — showing entries from your last sync.',
                style: TextStyle(color: AppColors.info),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => setState(() => _status = _Status.unavailable),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction, size: 72, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Not available yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sending this to the browser extension requires the TruthID '
              'extension, which is not built yet. Nothing was sent.',
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

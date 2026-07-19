import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/session_creator.dart';
import '../services/vault_key_service.dart';
import '../services/vault_publish_service.dart';
import '../services/vault_repository.dart';
import '../services/vault_sync_service.dart';
import '../theme.dart';
import 'pinning_providers_screen.dart';
import 'vault_backup_screen.dart';
import 'vault_device_permissions_screen.dart';
import 'vault_entry_detail_screen.dart';
import 'vault_entry_form_screen.dart';
import 'vault_profiles_screen.dart';

// Leitura + escrita do Vault no mobile — 13.8 trouxe a leitura, a Sessão 97
// trouxe criar/editar/apagar senha e publicar, condicionado a canWriteVault
// (concedido só pelo Desktop, ver PROJECT_STATE.md). O conteúdo real vem do
// VaultSyncService (on-chain → IPFS → verificação de hash → decifra).
class VaultScreen extends StatefulWidget {
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final VaultSyncService? vaultSyncService;
  final VaultKeyService? vaultKeyService;
  final VaultRepository? vaultRepository;
  final BundlerConfigService? bundlerConfigService;
  final VaultPublishService? vaultPublishService;

  const VaultScreen({
    super.key,
    this.blockchainService,
    this.localStorageService,
    this.deviceKeyService,
    this.vaultSyncService,
    this.vaultKeyService,
    this.vaultRepository,
    this.bundlerConfigService,
    this.vaultPublishService,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final DeviceKeyService _keyService;
  late final VaultSyncService _syncService;
  late final VaultKeyService _vaultKeyService;
  late final VaultRepository _repository;
  late final BundlerConfigService _bundlerConfigService;
  VaultPublishService? _publishService;

  bool _isLoading = true;
  bool _isPaired = false;
  bool _isRetryingVaultKey = false;
  VaultSyncStatus? _status;
  List<VaultEntry> _entries = const [];
  String? _error;
  String _query = '';

  bool _canWrite = false;
  String? _identityId;
  int _pendingChanges = 0;
  EthereumAddress? _smartAccountAddress;
  bool _publishing = false;
  String? _publishError;
  bool _justPublished = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _syncService = widget.vaultSyncService ??
        VaultSyncService(blockchainService: _blockchain);
    _vaultKeyService = widget.vaultKeyService ??
        VaultKeyService(deviceKeyService: _keyService);
    _repository = widget.vaultRepository ?? VaultRepository();
    _bundlerConfigService = widget.bundlerConfigService ?? BundlerConfigService();
    _publishService = widget.vaultPublishService;
    _load();
  }

  // Tenta buscar e decifrar de novo a vault key direto do que já está
  // gravado on-chain (deviceVaultKeys) — não depende de re-parear o device.
  // Cobre o caso em que a 1a tentativa (durante o pareamento) foi
  // interrompida, ex: Android matou o app em background.
  Future<void> _retryVaultKey() async {
    setState(() => _isRetryingVaultKey = true);

    final recovered = await _vaultKeyService.tryRecoverFromChain(_blockchain);
    if (recovered) {
      await _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vault key still not available on-chain.'),
        ),
      );
    }

    if (mounted) setState(() => _isRetryingVaultKey = false);
  }

  // Mesmo padrão de resolução device→identidade de sessions_screen.dart:
  // checa on-chain em toda execução (auto-descoberta e revogação), só então
  // sincroniza o vault.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final address = await _keyService.getDeviceAddress();
    var identityId = await _storage.getPairedIdentityId();

    final device = await _blockchain.getDevice(address);
    if (device != null && !device.revoked) {
      identityId ??= device.identityId.toString();
      await _storage.savePairedIdentity(identityId);
    } else if (identityId != null) {
      await _storage.clearPairedIdentity();
      identityId = null;
    }

    if (identityId == null) {
      if (mounted) {
        setState(() {
          _isPaired = false;
          _isLoading = false;
        });
      }
      return;
    }

    final outcome = await _syncService.sync(BigInt.parse(identityId));
    final canWrite = await _repository.canWriteVault(address);
    final pending = await _repository.pendingChanges();
    if (mounted) {
      setState(() {
        _isPaired = true;
        _status = outcome.status;
        _entries = outcome.entries;
        _error = outcome.error;
        _isLoading = false;
        _canWrite = canWrite;
        _identityId = identityId;
        _pendingChanges = pending;
      });
    }

    // Resolver a smart account depende do username — segue em paralelo, sem
    // bloquear a tela (mesmo padrão de sessions_screen.dart). Necessária só
    // pro botão Publicar (sender da UserOp de updateVault). Chamado
    // incondicionalmente (achado real, Sessão 135: um username nunca
    // resolvido ficava travado pra sempre sem retry — `_resolveSmartAccount`
    // agora tenta de novo via `resolvePairedUsername` antes de desistir).
    _resolveSmartAccount(identityId);
  }

  Future<void> _resolveSmartAccount(String identityId) async {
    try {
      final username = await resolvePairedUsername(
        storage: _storage,
        blockchain: _blockchain,
        identityId: identityId,
      );
      if (username == null) return;

      final identity = await _blockchain.getIdentityByUsername(username);
      if (identity == null) return;
      if (mounted) setState(() => _smartAccountAddress = identity.controller);
    } catch (_) {
      // Informativo — falha de rede aqui só desabilita o botão de publicar.
    }
  }

  Future<void> _publish() async {
    final smartAccountAddress = _smartAccountAddress;
    if (smartAccountAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not resolve your smart account. Check your connection.')),
      );
      return;
    }

    setState(() { _publishing = true; _publishError = null; });
    try {
      if (_publishService == null) {
        final bundlerConfig = await _bundlerConfigService.getConfig();
        _publishService = VaultPublishService(
          repository: _repository,
          sessionCreator: SessionCreator(
            blockchainService: _blockchain,
            deviceKeyService: _keyService,
            bundlerClient: PimlicoBundlerClient(
              bundlerUrl: pimlicoBundlerUrl(
                apiKey: bundlerConfig.apiKey,
                network: bundlerConfig.network,
              ),
            ),
          ),
        );
      }
      await _publishService!.publish(smartAccountAddress);
      final pending = await _repository.pendingChanges();
      if (mounted) {
        setState(() { _publishing = false; _pendingChanges = pending; _justPublished = true; });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _justPublished = false);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _publishing = false; _publishError = '$e'; });
    }
  }

  Future<void> _openNewEntry() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VaultEntryFormScreen(repository: _repository)),
    );
    if (saved == true) _load();
  }

  // Favoritos primeiro — partição em vez de sort com comparador, já que
  // List.sort do Dart não garante estabilidade (diferente do JS): separar
  // em duas listas e concatenar preserva a ordem relativa dentro de cada
  // grupo sem depender disso.
  List<VaultEntry> get _sortedEntries => [
        ..._entries.where((e) => e.favorite),
        ..._entries.where((e) => !e.favorite),
      ];

  List<VaultEntry> get _filteredEntries {
    if (_query.isEmpty) return _sortedEntries;
    final q = _query.toLowerCase();
    return _sortedEntries
        .where((e) =>
            e.site.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.profiles.any((p) => p.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _toggleFavorite(VaultEntry entry) async {
    final newValue = !entry.favorite;
    try {
      await _repository.setFavorite(entry.id, newValue);
      final pending = await _repository.pendingChanges();
      if (!mounted) return;
      setState(() {
        _entries = _entries
            .map((e) => e.id == entry.id ? e.copyWith(favorite: newValue) : e)
            .toList();
        _pendingChanges = pending;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update favorite: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isPaired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'Device not paired',
                style: TextStyle(fontSize: 18, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pair this device with an identity to see your vault.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final showList = _status == VaultSyncStatus.synced ||
        _status == VaultSyncStatus.offlineUsingCache;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Vault',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              // Fora da guarda de _canWrite de propósito: export/import não
              // dependem de permissão de escrita on-chain (só leem/escrevem
              // o cache local deste device) — mesmo device só-leitura pode
              // fazer backup do que já vê.
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: 'Backup / restore',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VaultBackupScreen(repository: _repository),
                  ),
                ),
              ),
              if (_canWrite) ...[
                IconButton(
                  icon: const Icon(Icons.cloud_outlined),
                  tooltip: 'Pinning providers',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PinningProvidersScreen(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.sell_outlined),
                  tooltip: 'Manage profiles',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VaultProfilesScreen(repository: _repository),
                    ),
                  ).then((_) => _load()),
                ),
                if (_identityId != null)
                  IconButton(
                    icon: const Icon(Icons.security),
                    tooltip: 'Device permissions',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VaultDevicePermissionsScreen(
                          identityId: _identityId!,
                          repository: _repository,
                        ),
                      ),
                    ).then((_) => _load()),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New entry',
                  onPressed: _openNewEntry,
                ),
              ],
            ],
          ),
          Text(
            _canWrite
                ? 'You can add, edit and publish entries from this device.'
                : 'Read-only here — manage entries from the Desktop app.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (_canWrite) ...[
            const SizedBox(height: 12),
            _buildPublishBanner(),
          ],
          const SizedBox(height: 12),
          if (_status == VaultSyncStatus.offlineUsingCache) ...[
            Card(
              color: AppColors.infoBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Offline — showing entries from your last sync.',
                  style: TextStyle(color: AppColors.info),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_status == VaultSyncStatus.noVaultPublished)
            _buildEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No vault published yet',
              subtitle: 'Publish a vault from the Desktop app first.',
            )
          else if (_status == VaultSyncStatus.noVaultKey)
            _buildEmptyState(
              icon: Icons.key_off,
              title: 'Vault key not available',
              subtitle:
                  'This can happen if the app was interrupted during '
                  'pairing. No need to re-pair — just try again.',
              action: _isRetryingVaultKey
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: _retryVaultKey,
                      child: const Text('Try again'),
                    ),
            )
          else if (_status == VaultSyncStatus.syncFailedNoCache)
            _buildEmptyState(
              icon: Icons.cloud_off,
              title: 'Could not load your vault',
              subtitle: _error ?? 'Check your connection and try again.',
            )
          else if (showList) ...[
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by site, username or profile',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            if (_filteredEntries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    _entries.isEmpty
                        ? 'No entries yet'
                        : 'No entries match your search',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              ..._filteredEntries.map(
                (e) => _VaultEntryCard(
                  entry: e,
                  canWrite: _canWrite,
                  onTap: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => VaultEntryDetailScreen(
                        entry: e,
                        canWrite: _canWrite,
                        repository: _repository,
                      ),
                    ),
                  ).then((deleted) { if (deleted == true) _load(); }),
                  onToggleFavorite: () => _toggleFavorite(e),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPublishBanner() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _justPublished
                        ? 'Published ✓'
                        : _pendingChanges > 0
                            ? '$_pendingChanges pending change${_pendingChanges > 1 ? "s" : ""}'
                            : 'Everything published',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
                ElevatedButton(
                  onPressed: (_publishing || _pendingChanges == 0) ? null : _publish,
                  child: Text(_publishing ? 'Publishing...' : 'Publish'),
                ),
              ],
            ),
            if (_publishError != null) ...[
              const SizedBox(height: 8),
              Text(_publishError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}

class _VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final bool canWrite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  const _VaultEntryCard({
    required this.entry,
    required this.canWrite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: IconButton(
          icon: Icon(entry.favorite ? Icons.star : Icons.star_border),
          color: entry.favorite ? AppColors.accent : AppColors.textMuted,
          tooltip: entry.favorite
              ? 'Remove from favorites'
              : 'Add to favorites',
          onPressed: canWrite ? onToggleFavorite : null,
        ),
        title: Text(entry.site,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.username,
                style: const TextStyle(color: AppColors.textMuted)),
            if (entry.profiles.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: entry.profiles
                    .map((p) => Chip(
                          label: Text(p, style: const TextStyle(fontSize: 11)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        // Placeholder fixo, não derivado do tamanho real da senha — evita
        // vazar o comprimento da senha na lista.
        trailing: const Text(
          '••••••••',
          style: TextStyle(color: AppColors.textMuted, letterSpacing: 2),
        ),
      ),
    );
  }
}

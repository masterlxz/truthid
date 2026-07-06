import 'package:flutter/material.dart';

import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/vault_repository.dart';
import '../services/vault_sync_service.dart';
import '../theme.dart';
import 'vault_entry_detail_screen.dart';

// Leitura do Vault no mobile (13.8) — só leitura, sem add/edit/delete (isso
// continua exclusivo do Desktop, ver PROJECT_STATE.md). O conteúdo real vem
// do VaultSyncService (on-chain → IPFS → verificação de hash → decifra),
// nunca de um vault local que ninguém popularia.
class VaultScreen extends StatefulWidget {
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final VaultSyncService? vaultSyncService;

  const VaultScreen({
    super.key,
    this.blockchainService,
    this.localStorageService,
    this.deviceKeyService,
    this.vaultSyncService,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final DeviceKeyService _keyService;
  late final VaultSyncService _syncService;

  bool _isLoading = true;
  bool _isPaired = false;
  VaultSyncStatus? _status;
  List<VaultEntry> _entries = const [];
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _syncService = widget.vaultSyncService ??
        VaultSyncService(blockchainService: _blockchain);
    _load();
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
    if (mounted) {
      setState(() {
        _isPaired = true;
        _status = outcome.status;
        _entries = outcome.entries;
        _error = outcome.error;
        _isLoading = false;
      });
    }
  }

  List<VaultEntry> get _filteredEntries {
    if (_query.isEmpty) return _entries;
    final q = _query.toLowerCase();
    return _entries
        .where((e) =>
            e.site.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.profiles.any((p) => p.toLowerCase().contains(q)))
        .toList();
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
          const Text('Vault',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Read-only here — manage entries from the Desktop app.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
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
              subtitle: 'Re-pair this device with Desktop to receive it.',
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VaultEntryDetailScreen(entry: e),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
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
          ],
        ),
      ),
    );
  }
}

class _VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  const _VaultEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
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

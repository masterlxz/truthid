import 'package:flutter/material.dart';

import '../services/blockchain_service.dart';
import '../services/vault_repository.dart';
import '../theme.dart';

class _DeviceRow {
  final DeviceInfo device;
  final bool canWrite;
  const _DeviceRow({required this.device, required this.canWrite});
}

// Gerenciar permissão de escrita (canWrite) por device — mirror da seção
// "Permissões por device" do Desktop (VaultManagement.tsx). Só alcançável
// quando o device tem canWriteVault (checado em vault_screen.dart antes de
// navegar pra cá), mesmo gate que já protege "Manage profiles"/"New entry".
// Trava de UX, não de contrato — Vault::set_device_permission (Rust) é
// chamável por qualquer processo com acesso de escrita ao arquivo.
class VaultDevicePermissionsScreen extends StatefulWidget {
  final String identityId;
  final VaultRepository? repository;
  final BlockchainService? blockchainService;

  const VaultDevicePermissionsScreen({
    super.key,
    required this.identityId,
    this.repository,
    this.blockchainService,
  });

  @override
  State<VaultDevicePermissionsScreen> createState() =>
      _VaultDevicePermissionsScreenState();
}

class _VaultDevicePermissionsScreenState
    extends State<VaultDevicePermissionsScreen> {
  late final VaultRepository _repository;
  late final BlockchainService _blockchain;
  List<_DeviceRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identityId = BigInt.parse(widget.identityId);
      final pubKeys = await _blockchain.getDevicesForIdentity(identityId);
      final devices = await Future.wait(pubKeys.map(_blockchain.getDevice));
      final activeDevices = devices
          .whereType<DeviceInfo>()
          .where((d) => !d.revoked)
          .toList();
      final permissions = await _repository.listDevicePermissions();

      final rows = activeDevices.map((d) {
        var canWrite = false;
        for (final p in permissions) {
          if (p.pubKey.toLowerCase() == d.pubKey.toLowerCase()) {
            canWrite = p.canWrite;
            break;
          }
        }
        return _DeviceRow(device: d, canWrite: canWrite);
      }).toList();

      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _toggle(String pubKey, bool canWrite) async {
    setState(() => _error = null);
    try {
      await _repository.setDevicePermission(pubKey, canWrite);
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  String _shorten(String pubKey) => pubKey.length > 10
      ? '${pubKey.substring(0, 6)}…${pubKey.substring(pubKey.length - 4)}'
      : pubKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device permissions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Controls whether a paired device can add, edit and '
                    'publish entries in this Vault. By default a new device '
                    'is read-only.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                  Expanded(
                    child: _rows.isEmpty
                        ? const Center(
                            child: Text('No active devices registered.',
                                style: TextStyle(color: AppColors.textMuted)),
                          )
                        : ListView(
                            children: _rows
                                .map((row) => Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text(
                                          row.device.label.isNotEmpty
                                              ? row.device.label
                                              : _shorten(row.device.pubKey),
                                        ),
                                        subtitle: Text(
                                          _shorten(row.device.pubKey),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: TextButton(
                                          onPressed: () => _toggle(
                                            row.device.pubKey,
                                            !row.canWrite,
                                          ),
                                          child: Text(
                                            row.canWrite
                                                ? '✓ Can write'
                                                : 'Read only',
                                            style: TextStyle(
                                              color: row.canWrite
                                                  ? AppColors.success
                                                  : AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

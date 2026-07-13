import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/vault_repository.dart';
import '../theme.dart';
import '../widgets/info_row.dart';
import 'vault_entry_form_screen.dart';

// Detalhe de uma entrada do Vault. Editar/apagar só aparece quando o device
// tem canWriteVault (ver PROJECT_STATE.md, Sessão 97) — quem navega pra cá
// já checou isso (vault_screen.dart). Senha escondida por padrão.
class VaultEntryDetailScreen extends StatefulWidget {
  final VaultEntry entry;
  final bool canWrite;
  final VaultRepository? repository;

  const VaultEntryDetailScreen({
    super.key,
    required this.entry,
    this.canWrite = false,
    this.repository,
  });

  @override
  State<VaultEntryDetailScreen> createState() =>
      _VaultEntryDetailScreenState();
}

class _VaultEntryDetailScreenState extends State<VaultEntryDetailScreen> {
  late final VaultRepository _repository;
  late VaultEntry _entry;
  bool _passwordVisible = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _entry = widget.entry;
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied!')),
    );
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VaultEntryFormScreen(entry: _entry, repository: _repository),
      ),
    );
    if (saved == true) {
      final entries = await _repository.listEntries();
      final updated = entries.where((e) => e.id == _entry.id).toList();
      if (mounted && updated.isNotEmpty) {
        setState(() => _entry = updated.first);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('This will remove "${_entry.site}" from your vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    await _repository.deleteEntry(_entry.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.site),
        actions: widget.canWrite
            ? [
                IconButton(icon: const Icon(Icons.edit), onPressed: _deleting ? null : _edit),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleting ? null : _delete,
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow(label: 'Site', value: entry.site),
            if (entry.url.isNotEmpty) ...[
              const SizedBox(height: 8),
              _LinkRow(url: entry.url),
            ],
            const SizedBox(height: 8),
            _CopyableRow(
              label: 'Username',
              value: entry.username,
              onCopy: () => _copy('Username', entry.username),
            ),
            const SizedBox(height: 8),
            _CopyableRow(
              label: 'Password',
              value: entry.password,
              masked: !_passwordVisible,
              onToggleVisibility: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
              onCopy: () => _copy('Password', entry.password),
            ),
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(label: 'Notes', value: entry.notes),
            ],
            if (entry.profiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children:
                    entry.profiles.map((p) => Chip(label: Text(p))).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String url;
  const _LinkRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => launchUrl(
        Uri.parse(url.contains('://') ? url : 'https://$url'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Text('URL: ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Expanded(
              child: Text(
                url,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  color: AppColors.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  final bool masked;
  final VoidCallback? onToggleVisibility;
  final VoidCallback onCopy;

  const _CopyableRow({
    required this.label,
    required this.value,
    this.masked = false,
    this.onToggleVisibility,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Expanded(
            child: Text(
              // Máscara de tamanho fixo, não proporcional ao valor real —
              // evita vazar o comprimento da senha mesmo na tela de detalhe.
              masked ? '••••••••' : value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
          if (onToggleVisibility != null)
            IconButton(
              icon: Icon(masked ? Icons.visibility : Icons.visibility_off,
                  size: 20, color: AppColors.textMuted),
              onPressed: onToggleVisibility,
            ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: AppColors.textMuted),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

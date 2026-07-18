import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/totp_service.dart';
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
            if (entry.totpSecret != null && entry.totpSecret!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _TotpCodeRow(
                secret: entry.totpSecret!,
                onCopy: (code) => _copy('2FA code', code),
              ),
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

// Mostra o código TOTP atual (RFC 6238), com contagem regressiva de 30s —
// mesmo padrão de Timer.periodic + cancel-em-dispose já usado em
// show_device_qr_screen.dart, adaptado pra um tick de 1s em vez de polling.
class _TotpCodeRow extends StatefulWidget {
  final String secret;
  final void Function(String code) onCopy;

  const _TotpCodeRow({required this.secret, required this.onCopy});

  @override
  State<_TotpCodeRow> createState() => _TotpCodeRowState();
}

class _TotpCodeRowState extends State<_TotpCodeRow> {
  static const _tickInterval = Duration(seconds: 1);
  Timer? _tickTimer;
  String _code = '······';
  int _remaining = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick();
    _tickTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    try {
      final code = generateTotpCode(widget.secret, now);
      if (mounted) {
        setState(() {
          _code = code;
          _remaining = secondsRemaining(now);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text('2FA: $_error', style: const TextStyle(color: AppColors.danger));
    }
    final formatted = '${_code.substring(0, 3)} ${_code.substring(3)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text('2FA: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Expanded(
            child: Text(formatted,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
          ),
          Text('${_remaining}s', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: AppColors.textMuted),
            onPressed: () => widget.onCopy(_code),
          ),
        ],
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

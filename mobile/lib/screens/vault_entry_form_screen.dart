import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/totp_service.dart';
import '../services/vault_repository.dart';
import '../services/webauthn_service.dart' as webauthn;
import '../theme.dart';

// Tela compartilhada de criar/editar uma entrada do vault — mirror do
// `EntryForm` do Desktop (`VaultManagement.tsx`). `entry` null = criar.
// Só alcançável quando o device tem canWriteVault (checado por quem navega
// pra cá, ver vault_screen.dart), ver PROJECT_STATE.md, Sessão 97.
class VaultEntryFormScreen extends StatefulWidget {
  final VaultEntry? entry;
  final VaultRepository? repository;

  const VaultEntryFormScreen({super.key, this.entry, this.repository});

  @override
  State<VaultEntryFormScreen> createState() => _VaultEntryFormScreenState();
}

class _VaultEntryFormScreenState extends State<VaultEntryFormScreen> {
  late final VaultRepository _repository;
  final _siteCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _totpSecretCtrl = TextEditingController();

  List<String> _profileOptions = [];
  final Set<String> _selectedProfiles = {};
  bool _showPassword = false;
  bool _loadingProfiles = true;
  bool _saving = false;
  String? _error;
  String? _totpError;
  Passkey? _passkey;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    final entry = widget.entry;
    if (entry != null) {
      _siteCtrl.text = entry.site;
      _urlCtrl.text = entry.url;
      _usernameCtrl.text = entry.username;
      _passwordCtrl.text = entry.password;
      _notesCtrl.text = entry.notes;
      _selectedProfiles.addAll(entry.profiles);
      _totpSecretCtrl.text = entry.totpSecret ?? '';
      _passkey = entry.passkey;
    }
    _loadProfileOptions();
  }

  // Deriva um hostname pra usar como RP ID — tenta a URL, cai pro nome do
  // site (sanitizado) se estiver vazia/inválida. Sem redução pra domínio
  // registrável (eTLD+1) nesta fase, mesmo critério do Desktop
  // (VaultManagement.tsx, hostnameOf).
  String _hostnameOf(String url, String site) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    final sanitized = site.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '');
    return sanitized.isNotEmpty ? sanitized : 'unknown';
  }

  void _generatePasskey() {
    final rpId = _hostnameOf(_urlCtrl.text, _siteCtrl.text);
    final random = Random.secure();
    final challenge = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final created = webauthn.createPasskey(
      rpId: rpId,
      challenge: challenge,
      origin: 'https://$rpId',
    );
    setState(() {
      _passkey = Passkey(
        rpId: rpId,
        credentialIdB64: created.credentialIdB64,
        userHandleB64: created.userHandleB64,
        privateKeyHex: created.privateKeyHex,
        signCount: created.signCount,
        createdAt: DateTime.fromMillisecondsSinceEpoch(created.createdAt * 1000, isUtc: true),
      );
    });
  }

  Future<void> _loadProfileOptions() async {
    final names = await _repository.listProfileNames();
    if (mounted) setState(() { _profileOptions = names; _loadingProfiles = false; });
  }

  @override
  void dispose() {
    _siteCtrl.dispose();
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    _totpSecretCtrl.dispose();
    super.dispose();
  }

  bool get _formInvalid =>
      _siteCtrl.text.trim().isEmpty ||
      _usernameCtrl.text.trim().isEmpty ||
      _passwordCtrl.text.trim().isEmpty;

  void _onTotpChanged(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _totpError = null;
        return;
      }
      try {
        parseTotpSecret(value);
        _totpError = null;
      } catch (e) {
        _totpError = '$e';
      }
    });
  }

  Future<void> _save() async {
    String? totpSecret;
    if (_totpSecretCtrl.text.trim().isNotEmpty) {
      try {
        totpSecret = parseTotpSecret(_totpSecretCtrl.text);
      } catch (e) {
        setState(() => _totpError = '$e');
        return;
      }
    }

    setState(() { _saving = true; _error = null; });
    try {
      if (_isEditing) {
        await _repository.updateEntry(widget.entry!.copyWith(
          site: _siteCtrl.text.trim(),
          url: _urlCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          profiles: _selectedProfiles.toList(),
          totpSecret: totpSecret,
          passkey: _passkey,
        ));
      } else {
        await _repository.addEntry(
          site: _siteCtrl.text.trim(),
          url: _urlCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          profiles: _selectedProfiles.toList(),
          totpSecret: totpSecret,
          passkey: _passkey,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit entry' : 'New entry')),
      body: _loadingProfiles
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _siteCtrl,
                    decoration: const InputDecoration(labelText: 'Site *', hintText: 'ex: github.com'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(labelText: 'URL', hintText: 'https://...'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Username *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _totpSecretCtrl,
                    decoration: InputDecoration(
                      labelText: '2FA secret (optional)',
                      hintText: 'base32 secret or otpauth://... URI',
                      errorText: _totpError,
                    ),
                    onChanged: _onTotpChanged,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Passkey: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_passkey != null)
                        Expanded(
                          child: Text(_passkey!.rpId,
                              style: const TextStyle(color: AppColors.textMuted),
                              overflow: TextOverflow.ellipsis),
                        ),
                      TextButton(
                        onPressed: _generatePasskey,
                        child: Text(_passkey == null ? 'Gerar passkey' : 'Recriar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Profiles', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_profileOptions.isEmpty)
                    const Text(
                      'No profiles created yet — create one from the Desktop app.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: _profileOptions.map((p) {
                        final selected = _selectedProfiles.contains(p);
                        return FilterChip(
                          label: Text(p),
                          selected: selected,
                          onSelected: (v) => setState(
                              () => v ? _selectedProfiles.add(p) : _selectedProfiles.remove(p)),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton(
                    onPressed: (_saving || _formInvalid || _totpError != null) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}

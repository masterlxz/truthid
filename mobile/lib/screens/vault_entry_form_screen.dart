import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/totp_service.dart';
import '../services/vault_repository.dart';
import '../services/webauthn_service.dart' as webauthn;
import '../theme.dart';
import '../utils/password_generator.dart';
import '../utils/password_strength.dart';

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

  // Abre o painel de opções do gerador de senha (mirror do painel inline do
  // Desktop em VaultManagement.tsx) e devolve a senha escolhida, ou null se
  // o usuário cancelar sem confirmar. showModalBottomSheet + StatefulBuilder
  // é o único precedente de painel de opções com estado mutável no Mobile
  // (ver wallet_screen.dart, _showDepositSheet).
  Future<void> _openPasswordGenerator() async {
    var options = const PasswordGeneratorOptions(
      length: 16,
      uppercase: true,
      lowercase: true,
      numbers: true,
      symbols: true,
    );
    var preview = '';
    String? error;

    void regenerate() {
      try {
        preview = generatePassword(options);
        error = null;
      } catch (e) {
        preview = '';
        error = '$e';
      }
    }

    regenerate();

    final generated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Generate password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Length', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: options.length <= 1
                          ? null
                          : () => setSheetState(() {
                                options = options.copyWith(length: options.length - 1);
                                regenerate();
                              }),
                    ),
                    Text('${options.length}', style: const TextStyle(fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setSheetState(() {
                        options = options.copyWith(length: options.length + 1);
                        regenerate();
                      }),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ('Uppercase', options.uppercase,
                        (bool v) => options.copyWith(uppercase: v)),
                    ('Lowercase', options.lowercase,
                        (bool v) => options.copyWith(lowercase: v)),
                    ('Numbers', options.numbers, (bool v) => options.copyWith(numbers: v)),
                    ('Symbols', options.symbols, (bool v) => options.copyWith(symbols: v)),
                  ].map((entry) {
                    final (label, selected, apply) = entry;
                    return FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (v) => setSheetState(() {
                        options = apply(v);
                        regenerate();
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview.isNotEmpty ? preview : '—',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Regenerate',
                        onPressed: () => setSheetState(regenerate),
                      ),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: preview.isEmpty ? null : () => Navigator.of(ctx).pop(preview),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Use this password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (generated != null) setState(() => _passwordCtrl.text = generated);
  }

  static const _strengthColors = [
    AppColors.danger,
    AppColors.warning,
    AppColors.accent,
    AppColors.success,
  ];

  Widget _buildStrengthMeter() {
    if (_passwordCtrl.text.isEmpty) return const SizedBox.shrink();
    final result = passwordStrength(_passwordCtrl.text);
    final color = _strengthColors[result.score];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 3 : 0),
                    decoration: BoxDecoration(
                      color: i <= result.score ? color : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Text(result.label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
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
                      ),
                      IconButton(
                        icon: const Icon(Icons.casino_outlined),
                        tooltip: 'Generate password',
                        onPressed: _openPasswordGenerator,
                      ),
                    ],
                  ),
                  _buildStrengthMeter(),
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

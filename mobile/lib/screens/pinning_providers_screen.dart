import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ipfs_pin_client.dart';
import '../services/pinning_provider_service.dart';
import '../theme.dart';
import '../l10n/l10n_extensions.dart';

enum _HealthStatus { idle, checking, ok, error }

// Config de provedores de pin do Mobile — mirror de
// `desktop/src/components/VaultSettings.tsx`, mas independente da config do
// Desktop (cada device guarda a própria, ver project/INDEX.md, Sessão 97).
class PinningProvidersScreen extends StatefulWidget {
  final PinningProviderService? providerService;

  const PinningProvidersScreen({super.key, this.providerService});

  @override
  State<PinningProvidersScreen> createState() => _PinningProvidersScreenState();
}

class _PinningProvidersScreenState extends State<PinningProvidersScreen> {
  late final PinningProviderService _service;
  List<PinningProvider> _providers = [];
  bool _loading = true;
  String? _error;
  final Map<int, _HealthStatus> _health = {};

  bool _addOpen = false;
  final _nameCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  String _kind = 'kubo';
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _service = widget.providerService ?? PinningProviderService();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final providers = await _service.load();
    if (mounted) setState(() { _providers = providers; _loading = false; });
  }

  Future<void> _saveAll(List<PinningProvider> updated) async {
    setState(() => _error = null);
    try {
      await _service.save(updated);
      setState(() { _providers = updated; _health.clear(); });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _handleRemove(int index) {
    final updated = [..._providers]..removeAt(index);
    _saveAll(updated);
  }

  Future<void> _handleCheck(int index) async {
    setState(() => _health[index] = _HealthStatus.checking);
    final ok = await _checkHealth(_providers[index]);
    if (mounted) {
      setState(() => _health[index] = ok ? _HealthStatus.ok : _HealthStatus.error);
    }
  }

  Future<bool> _checkHealth(PinningProvider p) async {
    final client = HttpClient();
    try {
      final base = p.endpointUrl.endsWith('/')
          ? p.endpointUrl.substring(0, p.endpointUrl.length - 1)
          : p.endpointUrl;
      final path = p.kind == 'kubo' ? '/api/v0/version' : '/pins?limit=1';
      final url = Uri.parse('$base$path');
      final request =
          p.kind == 'kubo' ? await client.postUrl(url) : await client.getUrl(url);
      if (p.apiKey.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${p.apiKey}');
      }
      final response = await request.close();
      await response.drain();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void _handleAddKuboDefault() {
    _saveAll([
      ..._providers,
      PinningProvider(
        name: context.l10n.pinningProvidersScreenKuboLocalDefaultName,
        kind: 'kubo',
        endpointUrl: 'http://localhost:5001',
      ),
    ]);
  }

  bool get _formInvalid =>
      _nameCtrl.text.trim().isEmpty ||
      _endpointCtrl.text.trim().isEmpty ||
      (_kind == 'psa' && _apiKeyCtrl.text.trim().isEmpty);

  void _handleFormAdd() {
    if (_formInvalid) return;
    _saveAll([
      ..._providers,
      PinningProvider(
        name: _nameCtrl.text.trim(),
        kind: _kind,
        endpointUrl: _endpointCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
      ),
    ]);
    _nameCtrl.clear();
    _endpointCtrl.clear();
    _apiKeyCtrl.clear();
    setState(() { _addOpen = false; _kind = 'kubo'; _showKey = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pinningProvidersScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.pinningProvidersScreenIntro,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  if (_providers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.l10n.pinningProvidersScreenEmptyState,
                              style: const TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _handleAddKuboDefault,
                            child: Text(context.l10n
                                .pinningProvidersScreenAddKuboDefaultButton),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._providers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final status = _health[i] ?? _HealthStatus.idle;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(p.name),
                          // kind (enum técnico 'kubo'/'psa') e endpointUrl (URL)
                          // são dado dinâmico/técnico, não texto de UI — não
                          // localizados. O separador '·' também não carrega
                          // conteúdo linguístico.
                          subtitle: Text('${p.kind} · ${p.endpointUrl}'),
                          leading: switch (status) {
                            _HealthStatus.ok => const Icon(Icons.check_circle, color: AppColors.success),
                            _HealthStatus.error => const Icon(Icons.error, color: AppColors.danger),
                            _HealthStatus.checking => const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            _HealthStatus.idle => const Icon(Icons.cloud_outlined, color: AppColors.textMuted),
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: context.l10n.pinningProvidersScreenTestTooltip,
                                onPressed: status == _HealthStatus.checking
                                    ? null
                                    : () => _handleCheck(i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                tooltip: context.l10n.pinningProvidersScreenRemoveTooltip,
                                onPressed: () => _handleRemove(i),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  if (!_addOpen)
                    OutlinedButton(
                      onPressed: () => setState(() => _addOpen = true),
                      child: Text(context.l10n.pinningProvidersScreenAddProviderButton),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                              labelText: context.l10n.pinningProvidersScreenNameLabel,
                              hintText: context.l10n.pinningProvidersScreenNameHint),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _kind,
                          decoration: InputDecoration(
                              labelText: context.l10n.pinningProvidersScreenTypeLabel),
                          items: [
                            DropdownMenuItem(
                                value: 'kubo',
                                child: Text(context.l10n
                                    .pinningProvidersScreenKindKuboOption)),
                            DropdownMenuItem(
                                value: 'psa',
                                child: Text(context.l10n
                                    .pinningProvidersScreenKindPsaOption)),
                          ],
                          onChanged: (v) => setState(() => _kind = v ?? 'kubo'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _endpointCtrl,
                          decoration: InputDecoration(
                            labelText:
                                context.l10n.pinningProvidersScreenEndpointUrlLabel,
                            hintText: _kind == 'kubo'
                                ? context.l10n
                                    .pinningProvidersScreenEndpointHintKubo
                                : context.l10n
                                    .pinningProvidersScreenEndpointHintPsa,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: !_showKey,
                          decoration: InputDecoration(
                            labelText: _kind == 'kubo'
                                ? context.l10n
                                    .pinningProvidersScreenApiKeyOptionalLabel
                                : context.l10n.pinningProvidersScreenApiKeyLabel,
                            hintText: _kind == 'kubo'
                                ? context.l10n
                                    .pinningProvidersScreenApiKeyOptionalHint
                                : context.l10n.pinningProvidersScreenApiKeyHint,
                            suffixIcon: IconButton(
                              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _showKey = !_showKey),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _formInvalid ? null : _handleFormAdd,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.background,
                                ),
                                child: Text(
                                    context.l10n.pinningProvidersScreenAddButton),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() { _addOpen = false; _showKey = false; }),
                                child: Text(context.l10n
                                    .pinningProvidersScreenCancelButton),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

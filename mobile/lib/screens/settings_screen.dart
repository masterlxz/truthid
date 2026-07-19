import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/bundler_config_service.dart';
import '../theme.dart';
import 'deeplink_self_test_screen.dart';
import 'security_screen.dart';

// Tela de configuracao do bundler (Pimlico ou custom). Permite ao usuario
// informar sua propria API key + rede, em vez de usar a chave do dev
// compilada no app (debito #27).
class SettingsScreen extends StatefulWidget {
  final BundlerConfigService? configService;

  const SettingsScreen({super.key, this.configService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late BundlerConfigService _configService;
  final _apiKeyCtrl = TextEditingController();
  final _networkCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _configService = widget.configService ?? BundlerConfigService();
    _load();
  }

  Future<void> _load() async {
    final config = await _configService.getConfig();
    _apiKeyCtrl.text = config.apiKey;
    _networkCtrl.text = config.network;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saved = null;
    });
    await _configService.saveConfig(
      apiKey: _apiKeyCtrl.text.trim(),
      network: _networkCtrl.text.trim(),
    );
    if (mounted) {
      setState(() {
        _saving = false;
        _saved = 'Settings saved. Changes apply on next login.';
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saved = null);
      });
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _networkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bundler Configuration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your bundler submits user operations to the blockchain on your behalf. You need your own API key (free at pimlico.io) — or connect a self-hosted bundler.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _apiKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Pimlico API Key',
                      hintText: 'pim_...',
                      helperText: 'Get a free key at dashboard.pimlico.io',
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _networkCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Network',
                      hintText: 'base',
                      helperText: 'base, base-sepolia, or custom bundler URL',
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : const Text('Save', style: TextStyle(fontSize: 16)),
                  ),
                  if (_saved != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _saved!,
                        style: const TextStyle(color: AppColors.success),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Why do I need my own key?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'TruthID is decentralized — there is no company server paying your blockchain fees. Your smart account holds ETH and pays the bundler directly. The API key is only to reach the bundler node.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.security, color: AppColors.textMuted),
                    title: const Text('Security'),
                    subtitle: const Text(
                      'App lock via your device biometrics or PIN',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SecurityScreen()),
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link, color: AppColors.textMuted),
                      title: const Text('Deep Link Self-Test'),
                      subtitle: const Text(
                        'Debug only — fires a truthid:// link at this app',
                        style: TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DeepLinkSelfTestScreen(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
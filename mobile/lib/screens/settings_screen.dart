import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/bundler_config_service.dart';
import '../theme.dart';
import '../l10n/l10n_extensions.dart';
import 'deeplink_self_test_screen.dart';
import 'guardian_status_screen.dart';
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
        _saved = context.l10n.settingsScreenSavedMessage;
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
      appBar: AppBar(title: Text(context.l10n.settingsScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.settingsScreenBundlerConfigTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.settingsScreenBundlerConfigIntro,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _apiKeyCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsScreenApiKeyLabel,
                      hintText: context.l10n.settingsScreenApiKeyHint,
                      helperText: context.l10n.settingsScreenApiKeyHelper,
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _networkCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsScreenNetworkLabel,
                      hintText: context.l10n.settingsScreenNetworkHint,
                      helperText: context.l10n.settingsScreenNetworkHelper,
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
                        : Text(context.l10n.settingsScreenSaveButton,
                            style: const TextStyle(fontSize: 16)),
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
                  Text(
                    context.l10n.settingsScreenWhyOwnKeyTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.settingsScreenWhyOwnKeyBody,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.people_outline, color: AppColors.textMuted),
                    title: Text(context.l10n.settingsScreenSocialRecoveryTitle),
                    subtitle: Text(
                      context.l10n.settingsScreenSocialRecoverySubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GuardianStatusScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.security, color: AppColors.textMuted),
                    title: Text(context.l10n.settingsScreenSecurityTitle),
                    subtitle: Text(
                      context.l10n.settingsScreenSecuritySubtitle,
                      style: const TextStyle(fontSize: 12),
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
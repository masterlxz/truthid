import 'package:flutter/material.dart';

import '../services/bundler_config_service.dart';
import '../services/locale_service.dart';
import '../theme.dart';
import '../l10n/l10n_extensions.dart';
import 'guardian_status_screen.dart';
import 'security_screen.dart';

// Nomes dos idiomas nunca são traduzidos — cada um aparece sempre no
// próprio idioma, mesma convenção do seletor do Desktop.
const _kLanguageNames = <String, String>{
  'en': 'English',
  'pt_BR': 'Português (Brasil)',
  'es': 'Español',
  'zh_CN': '中文',
};

// `locale` vem sempre de `Localizations.localeOf(context)` — o locale já
// resolvido de fato (nunca `null`, mesmo quando o usuário não escolheu
// nada manualmente e o app está seguindo o idioma do sistema).
String _languageDisplayName(Locale locale) {
  final key = locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
  return _kLanguageNames[key] ?? _kLanguageNames['en']!;
}

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

  void _showLanguageSheet(BuildContext context) {
    final current = Localizations.localeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.l10n.settingsScreenLanguageSheetTitle,
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final locale in LocaleService.supportedLocales)
              ListTile(
                title: Text(_languageDisplayName(locale)),
                trailing: locale.languageCode == current.languageCode &&
                        locale.countryCode == current.countryCode
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  LocaleService().setLocale(locale);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language, color: AppColors.textMuted),
                    title: Text(context.l10n.settingsScreenLanguageTitle),
                    subtitle: Text(
                      _languageDisplayName(Localizations.localeOf(context)),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _showLanguageSheet(context),
                  ),
                ],
              ),
            ),
    );
  }
}
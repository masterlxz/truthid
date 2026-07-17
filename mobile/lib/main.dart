import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/devices_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/deep_link_router.dart';
import 'services/deep_link_service.dart';
import 'theme.dart';

const _kAppVersion = '1.0.0';
const _kDonateAddress = '0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265';
const _kReleasesUrl =
    'https://api.github.com/repos/masterlxz/truthid/releases/latest';

// Precisa existir fora da árvore de widgets: `DeepLinkService` recebe URIs
// de fora do ciclo normal de build (stream do `app_links`) e precisa
// conseguir empurrar uma rota mesmo sem um `BuildContext` de widget à mão.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const TruthIDApp());
}

class TruthIDApp extends StatelessWidget {
  const TruthIDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'TruthID',
      theme: appTheme,
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

bool _isNewer(String latest, String current) {
  final l = latest.split('.').map(int.tryParse).toList();
  final c = current.split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final lv = (i < l.length ? l[i] : null) ?? 0;
    final cv = (i < c.length ? c[i] : null) ?? 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;
  String? _updateVersion;
  String? _updateUrl;
  bool _updateDismissed = false;
  final _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _deepLinkService.init(navigatorKey);
  }

  @override
  void dispose() {
    _deepLinkService.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_kReleasesUrl));
      req.headers.set('User-Agent', 'TruthID-Mobile');
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final tag = ((data['tag_name'] as String?) ?? '').replaceFirst('v', '');
      final url = (data['html_url'] as String?) ?? '';
      if (tag.isNotEmpty && _isNewer(tag, _kAppVersion) && mounted) {
        setState(() {
          _updateVersion = tag;
          _updateUrl = url;
        });
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }

  void _showDonationSheet() {
    var copied = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return _DonationSheet(
            copied: copied,
            onCopy: () async {
              await Clipboard.setData(
                const ClipboardData(text: _kDonateAddress),
              );
              setSheetState(() => copied = true);
              Future.delayed(
                const Duration(seconds: 2),
                () {
                  if (ctx.mounted) setSheetState(() => copied = false);
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openScanner() async {
    final payload = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (payload == null || !mounted) return;
    DeepLinkRouter.handlePayload(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TruthID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Support TruthID',
            onPressed: _showDonationSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_updateVersion != null && !_updateDismissed)
            _UpdateBanner(
              version: _updateVersion!,
              url: _updateUrl ?? '',
              onDismiss: () => setState(() => _updateDismissed = true),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                DevicesScreen(),
                SessionsScreen(),
                WalletScreen(),
                VaultScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openScanner,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        tooltip: 'Scan QR',
        child: const Icon(Icons.qr_code_scanner, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: AppColors.surface,
        child: Row(
          children: [
            Expanded(
              child: _NavTab(
                icon: Icons.phonelink_lock,
                label: 'Devices',
                selected: _currentIndex == 0,
                onTap: () => setState(() => _currentIndex = 0),
              ),
            ),
            Expanded(
              child: _NavTab(
                icon: Icons.verified_user,
                label: 'Sessions',
                selected: _currentIndex == 1,
                onTap: () => setState(() => _currentIndex = 1),
              ),
            ),
            // Espaço reservado pro notch do FAB central — 2 abas de cada lado.
            const SizedBox(width: 56),
            Expanded(
              child: _NavTab(
                icon: Icons.account_balance_wallet,
                label: 'Wallet',
                selected: _currentIndex == 2,
                onTap: () => setState(() => _currentIndex = 2),
              ),
            ),
            Expanded(
              child: _NavTab(
                icon: Icons.lock_outline,
                label: 'Vault',
                selected: _currentIndex == 3,
                onTap: () => setState(() => _currentIndex = 3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationSheet extends StatelessWidget {
  final bool copied;
  final VoidCallback onCopy;

  const _DonationSheet({required this.copied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Support TruthID',
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'TruthID is open source and free.\nIf it helps you, consider sending a tip.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: 'ethereum:$_kDonateAddress',
              size: 180,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            _kDonateAddress,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
            label: Text(copied ? 'Copied!' : 'Copy address'),
          ),
          const SizedBox(height: 10),
          Text(
            'Any EVM chain · 0.001 ETH suggested',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final String version;
  final String url;
  final VoidCallback onDismiss;

  const _UpdateBanner({
    required this.version,
    required this.url,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.accent.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.system_update, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'TruthID $version available',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Download',
                style: TextStyle(color: AppColors.accent, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16, color: AppColors.accent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

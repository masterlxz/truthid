import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/approval_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sessions_screen.dart';
import 'theme.dart';

const _kAppVersion = '1.0.0';
const _kReleasesUrl =
    'https://api.github.com/repos/masterlxz/truthid/releases/latest';

void main() {
  runApp(const TruthIDApp());
}

class TruthIDApp extends StatelessWidget {
  const TruthIDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
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

  Future<void> _openScanner() async {
    final payload = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (payload == null || !mounted) return;

    final action = payload['action'] as String?;

    if (action == 'truthid-auth') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ApprovalScreen(payload: payload)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unrecognized QR: ${action ?? "no action"}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TruthID')),
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
              children: const [DevicesScreen(), SessionsScreen()],
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
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavTab(
              icon: Icons.phonelink_lock,
              label: 'Devices',
              selected: _currentIndex == 0,
              onTap: () => setState(() => _currentIndex = 0),
            ),
            const SizedBox(width: 72),
            _NavTab(
              icon: Icons.verified_user,
              label: 'Sessions',
              selected: _currentIndex == 1,
              onTap: () => setState(() => _currentIndex = 1),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
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

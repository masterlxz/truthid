import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../services/app_lock_service.dart';
import '../theme.dart';

// Bloqueio do app via biometria/PIN/padrão/senha do próprio dispositivo —
// nunca uma senha nova cadastrada no TruthID. Ver AppLockGate em main.dart
// pra onde a flag persistida aqui é lida (overlay sobre RootScreen).
class SecurityScreen extends StatefulWidget {
  final AppLockService? lockService;

  const SecurityScreen({super.key, this.lockService});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late final AppLockService _lockService;
  bool _loading = true;
  bool _enabled = false;
  bool _deviceSupported = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lockService = widget.lockService ?? AppLockService();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _lockService.isEnabled();
    final supported = await _lockService.isDeviceSupported();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _deviceSupported = supported;
        _loading = false;
      });
    }
  }

  Future<void> _onChanged(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    if (value) {
      if (!_deviceSupported) {
        setState(() {
          _busy = false;
          _error = context.l10n.securityScreenNoBiometricsError;
        });
        return;
      }
      bool confirmed;
      try {
        confirmed = await _lockService.authenticate();
      } catch (_) {
        confirmed = false;
      }
      if (!confirmed) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = context.l10n.securityScreenAuthFailedError;
          });
        }
        return;
      }
    }

    await _lockService.setEnabled(value);
    if (mounted) {
      setState(() {
        _enabled = value;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.securityScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.securityScreenAppLockTitle),
                  subtitle: Text(
                    context.l10n.securityScreenAppLockSubtitle,
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: _enabled,
                  onChanged: (_busy || (!_enabled && !_deviceSupported))
                      ? null
                      : _onChanged,
                ),
                if (!_deviceSupported) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.l10n.securityScreenNoBiometricsWarning,
                      style: const TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
    );
  }
}

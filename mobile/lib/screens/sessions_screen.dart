import 'package:flutter/material.dart';
import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../theme.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _storage = LocalStorageService();
  final _blockchain = BlockchainService();
  final _keyService = DeviceKeyService();

  bool _isLoading = true;
  bool _isPaired = false;
  String? _pairedIdentityId;
  String? _deviceAddress;
  List<SessionInfo>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final identityId = await _storage.getPairedIdentityId();
    final address = await _keyService.getDeviceAddress();

    // Sem identidade pareada: só mostra a tela de "não pareado"
    if (identityId == null) {
      if (mounted) {
        setState(() {
          _isPaired = false;
          _deviceAddress = address;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // identityId foi salvo como String no storage — precisa converter para BigInt
      final sessions = await _blockchain.getSessionsForIdentity(BigInt.parse(identityId));

      if (mounted) {
        setState(() {
          _isPaired = true;
          _pairedIdentityId = identityId;
          _deviceAddress = address;
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPaired = true;
          _pairedIdentityId = identityId;
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Dispositivo não pareado — não temos identityId para consultar
    if (!_isPaired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'Device not paired',
                style: TextStyle(fontSize: 18, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pair this device with an identity to see active sessions.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final activeSessions = _sessions?.where((s) => !s.isRevoked).length ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Cabeçalho ────────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Identity #$_pairedIdentityId',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$activeSessions active',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Sessions are created by websites when you approve a login.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const Divider(height: 24),

          // ── Erro de leitura ───────────────────────────────────────────────
          if (_error != null)
            Card(
              color: AppColors.dangerBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Error loading sessions: $_error',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            )

          // ── Lista vazia ───────────────────────────────────────────────────
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No sessions found',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )

          // ── Cards de sessão ───────────────────────────────────────────────
          else
            ..._sessions!.map(
              (s) => _SessionCard(
                session: s,
                // Destaca visualmente se a sessão foi criada com este device
                isCurrentDevice: _deviceAddress != null &&
                    s.devicePubKey.toLowerCase() ==
                        _deviceAddress!.toLowerCase(),
              ),
            ),

          // ── Aviso: revogação requer desktop ──────────────────────────────
          const SizedBox(height: 16),
          Card(
            color: AppColors.warningBg,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To revoke sessions, use the desktop app. '
                      'Revocation requires the controller wallet.',
                      style: TextStyle(fontSize: 13, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card individual de sessão ─────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final SessionInfo session;
  final bool isCurrentDevice;

  const _SessionCard({required this.session, required this.isCurrentDevice});

  @override
  Widget build(BuildContext context) {
    // Mostra só os primeiros 10 chars do hash para identificação visual
    final shortHash = '${session.hashHex.substring(0, 10)}...';
    final dateStr = _formatDate(session.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.vpn_key, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortHash,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCurrentDevice
                        ? 'This device · $dateStr'
                        : dateStr,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(session.isRevoked ? 'Revoked' : 'Active'),
              backgroundColor: session.isRevoked
                  ? AppColors.surfaceAlt
                  : AppColors.successBg,
              labelStyle: TextStyle(
                fontSize: 12,
                color: session.isRevoked
                    ? AppColors.textMuted
                    : AppColors.success,
              ),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day} at $h:$m';
  }
}

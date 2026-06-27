import 'package:flutter/material.dart';
import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';

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
  String? _username;
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

    final identity = await _storage.getPairedIdentity();
    final address = await _keyService.getDeviceAddress();

    // Sem identidade pareada: só mostra a tela de "não pareado"
    if (identity == null) {
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
      final identityId = BigInt.parse(identity.identityId);
      final sessions = await _blockchain.getSessionsForIdentity(identityId);

      if (mounted) {
        setState(() {
          _isPaired = true;
          _username = identity.username;
          _deviceAddress = address;
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPaired = true;
          _username = identity.username;
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
              Icon(Icons.link_off, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Dispositivo não pareado',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Pareie este dispositivo com uma identidade para ver as sessões ativas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
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
                '@$_username',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$activeSessions ativas',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sessões são criadas pelos sites quando você aprova um login.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const Divider(height: 24),

          // ── Erro de leitura ───────────────────────────────────────────────
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Erro ao carregar sessões: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )

          // ── Lista vazia ───────────────────────────────────────────────────
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Nenhuma sessão encontrada',
                  style: TextStyle(color: Colors.grey.shade400),
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
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Para revogar sessões, use o app desktop. '
                      'A revogação exige a controller wallet.',
                      style: TextStyle(fontSize: 13, color: Colors.amber),
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
            const Icon(Icons.vpn_key, size: 20, color: Colors.grey),
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
                        ? 'Este device · $dateStr'
                        : dateStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(session.isRevoked ? 'Revogada' : 'Ativa'),
              backgroundColor: session.isRevoked
                  ? Colors.grey.shade200
                  : Colors.green.shade100,
              labelStyle: TextStyle(
                fontSize: 12,
                color: session.isRevoked
                    ? Colors.grey.shade600
                    : Colors.green.shade700,
              ),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day/$month às $hour:$min';
  }
}

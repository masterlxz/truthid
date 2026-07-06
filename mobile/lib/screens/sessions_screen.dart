import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';

import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/session_creator.dart';
import '../theme.dart';

class SessionsScreen extends StatefulWidget {
  // Injetáveis para testes — em produção usa os defaults.
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final BundlerConfigService? bundlerConfigService;
  final SessionCreator? sessionCreator;

  const SessionsScreen({
    super.key,
    this.blockchainService,
    this.localStorageService,
    this.deviceKeyService,
    this.bundlerConfigService,
    this.sessionCreator,
  });

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final DeviceKeyService _keyService;
  late final BundlerConfigService _bundlerConfigService;
  SessionCreator? _sessionCreator;

  bool _isLoading = true;
  bool _isPaired = false;
  String? _pairedIdentityId;
  String? _pairedUsername;
  String? _deviceAddress;
  List<SessionInfo>? _sessions;
  String? _error;

  // Smart account (controller) da identidade pareada — resolvida on-chain a
  // partir do username, mesma chamada que a ApprovalScreen já faz antes de
  // montar uma UserOp (14.9.5). Necessária como `sender` da UserOp de revoke.
  // O saldo em si (que também dependia dessa resolução) migrou pra WalletScreen.
  EthereumAddress? _smartAccountAddress;

  // Hash da sessão sendo revogada agora (null = nenhuma) — desabilita os
  // outros botões de revogar enquanto uma UserOp está em voo.
  String? _revokingHash;

  @override
  void initState() {
    super.initState();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _bundlerConfigService =
        widget.bundlerConfigService ?? BundlerConfigService();
    _sessionCreator = widget.sessionCreator;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final address = await _keyService.getDeviceAddress();
    var identityId = await _storage.getPairedIdentityId();
    var username = await _storage.getPairedUsername();

    // Checar on-chain em toda execução — detecta auto-descoberta e revogação
    final device = await _blockchain.getDevice(address);

    if (device != null && !device.revoked) {
      if (identityId == null) {
        // Auto-descoberta: device registrado on-chain mas não salvo localmente
        identityId = device.identityId.toString();
        await _storage.savePairedIdentity(identityId);
        _blockchain.getUsernameForIdentity(device.identityId).then((u) {
          if (u != null) {
            _storage.savePairedUsername(u);
            if (mounted) setState(() => _pairedUsername = u);
          }
        });
      }
    } else if (identityId != null) {
      // Device revogado ou removido — limpar storage
      await _storage.clearPairedIdentity();
      identityId = null;
      username = null;
    }

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
      final sessions = await _blockchain.getSessionsForIdentity(BigInt.parse(identityId));

      if (mounted) {
        setState(() {
          _isPaired = true;
          _pairedIdentityId = identityId;
          _pairedUsername = username;
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
          _pairedUsername = username;
          _isLoading = false;
          _error = e.toString();
        });
      }
    }

    // Resolver a smart account depende do username — segue em paralelo, sem
    // bloquear a lista de sessões (a lista já lê por identityId, que sempre
    // temos nesse ponto). Necessária só pro _revoke() (sender da UserOp).
    if (username != null) {
      _resolveSmartAccount(username);
    }
  }

  Future<void> _resolveSmartAccount(String username) async {
    try {
      final identity = await _blockchain.getIdentityByUsername(username);
      if (identity == null) return;
      if (mounted) setState(() => _smartAccountAddress = identity.controller);
    } catch (_) {
      // Informativo — falha de rede aqui só desabilita o botão de revoke.
    }
  }

  Future<void> _confirmRevoke(SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke session?'),
        content: const Text(
          'Any website using this session will be signed out immediately. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true) _revoke(session);
  }

  Future<void> _revoke(SessionInfo session) async {
    final smartAccountAddress = _smartAccountAddress;
    if (smartAccountAddress == null) {
      _showSnackBar('Could not resolve your smart account. Check your connection.');
      return;
    }

    setState(() => _revokingHash = session.hashHex);

    try {
      if (_sessionCreator == null) {
        final bundlerConfig = await _bundlerConfigService.getConfig();
        _sessionCreator = widget.sessionCreator ??
            SessionCreator(
              blockchainService: _blockchain,
              deviceKeyService: _keyService,
              bundlerClient: PimlicoBundlerClient(
                bundlerUrl: pimlicoBundlerUrl(
                  apiKey: bundlerConfig.apiKey,
                  network: bundlerConfig.network,
                ),
              ),
            );
      }

      await _sessionCreator!.revokeSession(
        smartAccountAddress: smartAccountAddress,
        sessionHash: session.hash,
      );

      if (mounted) setState(() => _revokingHash = null);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _revokingHash = null);
      _showSnackBar(
        'Could not revoke the session. Make sure your account has enough ETH for gas.',
      );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                _pairedUsername != null
                    ? '@$_pairedUsername'
                    : 'Identity #$_pairedIdentityId',
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
          const SizedBox(height: 12),

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
                isRevoking: _revokingHash == s.hashHex,
                revokeDisabled: _revokingHash != null || _smartAccountAddress == null,
                onRevoke: () => _confirmRevoke(s),
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
  final bool isRevoking;
  final bool revokeDisabled;
  final VoidCallback onRevoke;

  const _SessionCard({
    required this.session,
    required this.isCurrentDevice,
    required this.isRevoking,
    required this.revokeDisabled,
    required this.onRevoke,
  });

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
            if (session.isRevoked)
              const Chip(
                label: Text('Revoked'),
                backgroundColor: AppColors.surfaceAlt,
                labelStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
              )
            else if (isRevoking)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.logout, size: 20, color: AppColors.danger),
                tooltip: 'Revoke session',
                onPressed: revokeDisabled ? null : onRevoke,
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

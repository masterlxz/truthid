import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
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
    // Chamado incondicionalmente (não só `if (username != null)`) — achado
    // real, Sessão 135: o username podia nunca ter resolvido e ficava
    // travado pra sempre sem retry; `_resolveSmartAccount` agora tenta
    // resolver de novo via `resolvePairedUsername` antes de desistir.
    _resolveSmartAccount(identityId);
  }

  Future<void> _resolveSmartAccount(String identityId) async {
    try {
      final username = await resolvePairedUsername(
        storage: _storage,
        blockchain: _blockchain,
        identityId: identityId,
      );
      if (username == null) return;
      if (mounted) setState(() => _pairedUsername = username);

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
        title: Text(context.l10n.sessionsScreenRevokeDialogTitle),
        content: Text(
          context.l10n.sessionsScreenRevokeDialogContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.sessionsScreenCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.sessionsScreenRevokeConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) _revoke(session);
  }

  Future<void> _revoke(SessionInfo session) async {
    final smartAccountAddress = _smartAccountAddress;
    if (smartAccountAddress == null) {
      _showSnackBar(context.l10n.sessionsScreenSmartAccountUnresolvedError);
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
        context.l10n.sessionsScreenRevokeFailedError,
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
              Text(
                context.l10n.sessionsScreenNotPairedTitle,
                style: const TextStyle(fontSize: 18, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.sessionsScreenNotPairedBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
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
                    ? context.l10n.sessionsScreenUsernameHandle(_pairedUsername!)
                    : context.l10n.sessionsScreenIdentityFallback(_pairedIdentityId!),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                context.l10n.sessionsScreenActiveCount(activeSessions),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.sessionsScreenDescription,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),

          // ── Erro de leitura ───────────────────────────────────────────────
          if (_error != null)
            Card(
              color: AppColors.dangerBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.l10n.sessionsScreenLoadErrorPrefix(_error!),
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
                  context.l10n.sessionsScreenEmptyState,
                  style: const TextStyle(color: AppColors.textMuted),
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
                        ? context.l10n.sessionsScreenCurrentDeviceDate(dateStr)
                        : dateStr,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (session.isRevoked)
              Chip(
                label: Text(context.l10n.sessionsScreenRevokedChip),
                backgroundColor: AppColors.surfaceAlt,
                labelStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                tooltip: context.l10n.sessionsScreenRevokeTooltip,
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

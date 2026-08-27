import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web3dart/web3dart.dart';

import '../l10n/l10n_extensions.dart';
import '../models/smart_account_activity.dart';
import '../services/activity_cache_service.dart';
import '../services/arweave_client.dart'
    show ArweaveTxSummary, arweaveDefaultNode, getWalletBalance, getWalletTransactions;
import '../services/arweave_wallet_service.dart';
import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/session_creator.dart';
import '../services/smart_account_activity_scanner.dart';
import '../theme.dart';
import '../utils/eth_amount.dart' as eth_amount;

enum _WalletView { eth, arweave }

// Dashboard da smart account no mobile — porta de
// desktop/src/components/SmartAccountDashboard.tsx (14.10): saldo, resumo de
// custo por tipo de operação, histórico de atividade completo (desde o bloco
// de deploy dos contratos) e depósito/saque de ETH. Vive numa aba própria
// (ao contrário do saldo, que antes ficava dentro de SessionsScreen) pra
// espelhar a aba "dashboard" dedicada do Desktop.
//
// P67 (dashboard único ETH/Arweave): a visão Arweave foi incorporada aqui
// (portada de `arweave_wallet_screen.dart`, removido) via um toggle no topo
// — sem `Scaffold`/`AppBar` próprio, já que esta tela também não tem (herda
// a casca do `main.dart`).
class WalletScreen extends StatefulWidget {
  // Injetáveis para testes — em produção usa os defaults.
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final BundlerConfigService? bundlerConfigService;
  final SessionCreator? sessionCreator;
  final SmartAccountActivityScanner? activityScanner;
  final ActivityCacheService? activityCacheService;
  final ArweaveWalletService? arweaveWalletService;
  final Future<String> Function(String nodeUrl, String address) fetchArweaveBalance;
  final Future<List<ArweaveTxSummary>> Function(String nodeUrl, String address, {int first})
      fetchArweaveTransactions;

  const WalletScreen({
    super.key,
    this.blockchainService,
    this.localStorageService,
    this.deviceKeyService,
    this.bundlerConfigService,
    this.sessionCreator,
    this.activityScanner,
    this.activityCacheService,
    this.arweaveWalletService,
    this.fetchArweaveBalance = getWalletBalance,
    this.fetchArweaveTransactions = getWalletTransactions,
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final DeviceKeyService _keyService;
  late final BundlerConfigService _bundlerConfigService;
  late final SmartAccountActivityScanner _activityScanner;
  late final ActivityCacheService _activityCacheService;
  late final ArweaveWalletService _arweaveWalletService;
  SessionCreator? _sessionCreator;

  _WalletView _view = _WalletView.eth;

  bool _isLoading = true;
  bool _isPaired = false;
  String? _pairedIdentityId;
  String? _pairedUsername;

  EthereumAddress? _smartAccountAddress;
  BigInt? _balanceWei;
  bool _balanceLoading = false;

  List<SmartAccountActivity> _activities = [];
  bool _isScanning = false;
  ScanProgress? _scanProgress;
  String? _scanError;

  bool _arweaveLoading = true;
  bool _arweaveExists = false;
  String? _arweaveAddress;
  String? _arweaveBalanceWinston;
  bool _arweaveGenerating = false;
  String? _arweaveError;
  bool _arweaveCopied = false;

  List<ArweaveTxSummary> _arweaveHistory = [];
  bool _arweaveHistoryLoading = false;
  String? _arweaveHistoryError;

  String _activityLabel(BuildContext context, SmartAccountActivityType type) {
    switch (type) {
      case SmartAccountActivityType.sessionCreated:
        return context.l10n.walletScreenActivitySessionCreated;
      case SmartAccountActivityType.sessionRevoked:
        return context.l10n.walletScreenActivitySessionRevoked;
      case SmartAccountActivityType.sessionRevokedAll:
        return context.l10n.walletScreenActivitySessionRevokedAll;
      case SmartAccountActivityType.deviceRegistered:
        return context.l10n.walletScreenActivityDeviceRegistered;
      case SmartAccountActivityType.deviceRevoked:
        return context.l10n.walletScreenActivityDeviceRevoked;
    }
  }

  static const _revokedTypes = {
    SmartAccountActivityType.sessionRevoked,
    SmartAccountActivityType.sessionRevokedAll,
    SmartAccountActivityType.deviceRevoked,
  };

  @override
  void initState() {
    super.initState();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _bundlerConfigService =
        widget.bundlerConfigService ?? BundlerConfigService();
    _activityScanner = widget.activityScanner ?? SmartAccountActivityScanner();
    _activityCacheService = widget.activityCacheService ?? ActivityCacheService();
    _arweaveWalletService = widget.arweaveWalletService ?? ArweaveWalletService();
    _sessionCreator = widget.sessionCreator;
    _load();
    _loadArweaveWallet();
  }

  Future<void> _loadArweaveWallet() async {
    setState(() => _arweaveLoading = true);
    try {
      final exists = await _arweaveWalletService.exists();
      if (!mounted) return;
      setState(() => _arweaveExists = exists);
      if (!exists) return;
      final address = await _arweaveWalletService.address();
      if (!mounted) return;
      setState(() => _arweaveAddress = address);
      // Independentes entre si (cada uma só depende de `address`, cada uma
      // já é best-effort com seu próprio try/catch) — disparadas em paralelo
      // em vez de sequencial (achado P82 #8, inconsistente com
      // `act_as_guardian_screen.dart`, que já usa Future.wait pro mesmo
      // padrão).
      await Future.wait([
        _loadArweaveBalance(address),
        _loadArweaveHistory(address),
      ]);
    } catch (e) {
      if (mounted) setState(() => _arweaveError = '$e');
    } finally {
      if (mounted) setState(() => _arweaveLoading = false);
    }
  }

  // Best-effort — uma wallet sem tráfego ainda deve aparecer com endereço
  // mesmo se a consulta de saldo falhar.
  Future<void> _loadArweaveBalance(String address) async {
    try {
      final balance = await widget.fetchArweaveBalance(arweaveDefaultNode, address);
      if (mounted) setState(() => _arweaveBalanceWinston = balance);
    } catch (_) {
      if (mounted) setState(() => _arweaveBalanceWinston = null);
    }
  }

  Future<void> _loadArweaveHistory(String address) async {
    setState(() {
      _arweaveHistoryLoading = true;
      _arweaveHistoryError = null;
    });
    try {
      final history = await widget.fetchArweaveTransactions(arweaveDefaultNode, address);
      if (mounted) setState(() => _arweaveHistory = history);
    } catch (e) {
      if (mounted) setState(() => _arweaveHistoryError = '$e');
    } finally {
      if (mounted) setState(() => _arweaveHistoryLoading = false);
    }
  }

  Future<void> _handleGenerateArweaveWallet() async {
    setState(() {
      _arweaveError = null;
      _arweaveGenerating = true;
    });
    try {
      final address = await _arweaveWalletService.generate();
      if (!mounted) return;
      setState(() {
        _arweaveAddress = address;
        _arweaveExists = true;
      });
      await _loadArweaveBalance(address);
      await _loadArweaveHistory(address);
    } catch (e) {
      if (mounted) setState(() => _arweaveError = '$e');
    } finally {
      if (mounted) setState(() => _arweaveGenerating = false);
    }
  }

  Future<void> _handleCopyArweaveAddress() async {
    final address = _arweaveAddress;
    if (address == null) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _arweaveCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _arweaveCopied = false);
    });
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final address = await _keyService.getDeviceAddress();
    var identityId = await _storage.getPairedIdentityId();
    var username = await _storage.getPairedUsername();

    // Checar on-chain em toda execução — mesma dança de auto-descoberta/
    // revogação já usada em DevicesScreen/SessionsScreen.
    final device = await _blockchain.getDevice(address);

    if (device != null && !device.revoked) {
      if (identityId == null) {
        identityId = device.identityId.toString();
        await _storage.savePairedIdentity(identityId);
      }
    } else if (identityId != null) {
      await _storage.clearPairedIdentity();
      identityId = null;
      username = null;
    }

    if (identityId == null) {
      if (mounted) {
        setState(() {
          _isPaired = false;
          _isLoading = false;
        });
      }
      return;
    }

    // O scan de `getUsernameForIdentity` (varredura de logs) pode falhar por
    // um hiccup de rede pontual — sem retry aqui, um único load com falha
    // deixava o username nunca persistido, travando saldo/atividade pra
    // sempre (achado real, Sessão 134: identityId resolvido, username null
    // indefinidamente). `resolvePairedUsername` tenta de novo em todo load
    // enquanto não persistir (extraído como helper compartilhado na Sessão
    // 135 — o mesmo bug apareceu em mais telas).
    username ??= await resolvePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
    );

    if (mounted) {
      setState(() {
        _isPaired = true;
        _pairedIdentityId = identityId;
        _pairedUsername = username;
        _isLoading = false;
      });
    }

    if (username != null) {
      _resolveSmartAccountAndLoad(username, BigInt.parse(identityId));
    }
  }

  Future<void> _resolveSmartAccountAndLoad(String username, BigInt identityId) async {
    try {
      final identity = await _blockchain.getIdentityByUsername(username);
      if (identity == null) return;
      if (mounted) setState(() => _smartAccountAddress = identity.controller);
      _loadBalance(identity.controller);
      _loadActivity(identityId);
    } catch (_) {
      // Saldo/atividade são informativos — falha de rede aqui não deve travar a tela.
    }
  }

  Future<void> _loadBalance(EthereumAddress smartAccountAddress) async {
    if (mounted) setState(() => _balanceLoading = true);
    try {
      final balance = await _blockchain.getBalance(smartAccountAddress);
      if (mounted) setState(() => _balanceWei = balance);
    } catch (_) {
      // idem — informativo, não trava a tela.
    } finally {
      if (mounted) setState(() => _balanceLoading = false);
    }
  }

  Future<void> _loadActivity(BigInt identityId) async {
    final cached = await _activityCacheService.read(identityId);
    if (mounted && cached != null) setState(() => _activities = cached.activities);

    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanError = null;
      });
    }

    try {
      final latest = await _blockchain.getLatestBlockNumber();
      if (latest == null) throw Exception('Could not reach the network');

      final deployBlock = BlockchainService.deviceRegistryDeployBlock <
              BlockchainService.sessionRegistryDeployBlock
          ? BlockchainService.deviceRegistryDeployBlock
          : BlockchainService.sessionRegistryDeployBlock;
      final fromBlock = (cached != null && cached.lastScannedBlock < latest)
          ? cached.lastScannedBlock + 1
          : deployBlock;

      if (fromBlock > latest) {
        if (mounted) setState(() => _isScanning = false);
        return;
      }

      final baseActivities = cached?.activities ?? <SmartAccountActivity>[];
      final scanned = await _activityScanner.scan(
        identityId: identityId,
        fromBlock: fromBlock,
        toBlock: latest,
        onChunkScanned: (chunkActivities, progress) {
          if (mounted) {
            setState(() {
              _activities = [...baseActivities, ...chunkActivities];
              _scanProgress = progress;
            });
          }
        },
      );

      final merged = [...baseActivities, ...scanned];
      if (mounted) setState(() => _activities = merged);
      await _activityCacheService.write(identityId,
          lastScannedBlock: latest, activities: merged);
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _rescan() async {
    final identityId = _pairedIdentityId;
    if (identityId == null) return;
    final parsedId = BigInt.parse(identityId);
    await _activityCacheService.clear(parsedId);
    setState(() {
      _activities = [];
      _scanProgress = null;
      _scanError = null;
    });
    await _loadActivity(parsedId);
  }

  Future<void> _ensureSessionCreator() async {
    if (_sessionCreator != null) return;
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

  void _showDepositSheet() {
    final address = _smartAccountAddress;
    if (address == null) return;

    var copied = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.walletScreenDepositButton, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                context.l10n.walletScreenDepositSheetBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(data: 'ethereum:${address.hex}', size: 200),
              ),
              const SizedBox(height: 16),
              SelectableText(
                address.hex,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: address.hex));
                  setSheetState(() => copied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (ctx.mounted) setSheetState(() => copied = false);
                  });
                },
                icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
                label: Text(copied ? context.l10n.walletScreenCopiedButton : context.l10n.walletScreenCopyAddressButton),
              ),
              const SizedBox(height: 10),
              Text(context.l10n.walletScreenBaseMainnetOnly,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWithdrawSheet() async {
    final smartAccountAddress = _smartAccountAddress;
    final balance = _balanceWei;
    if (smartAccountAddress == null || balance == null || balance == BigInt.zero) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WithdrawSheet(
        availableBalanceWei: balance,
        onSubmit: (destination, amountWei) async {
          await _ensureSessionCreator();
          await _sessionCreator!.withdraw(
            smartAccountAddress: smartAccountAddress,
            destination: destination,
            amountWei: amountWei,
          );
        },
      ),
    );

    if (result == true) _loadBalance(smartAccountAddress);
  }

  String _formatEth(BigInt wei) {
    final eth = EtherAmount.fromBigInt(EtherUnit.wei, wei).getValueInUnit(EtherUnit.ether);
    return '${eth.toStringAsFixed(4)} ETH';
  }

  String _formatDate(int unixSeconds) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day} at $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isPaired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                context.l10n.walletScreenNotPairedTitle,
                style: const TextStyle(fontSize: 18, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.walletScreenNotPairedBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _view == _WalletView.eth ? _load : () => _loadArweaveWallet(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _pairedUsername != null
                ? context.l10n.walletScreenUsernameHandle(_pairedUsername!)
                : context.l10n.walletScreenIdentityFallback(_pairedIdentityId ?? ''),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // ── Toggle ETH ↔ Arweave (P67) ──────────────────────────────────────
          SegmentedButton<_WalletView>(
            segments: [
              ButtonSegment(value: _WalletView.eth, label: Text(context.l10n.walletScreenToggleEth)),
              ButtonSegment(value: _WalletView.arweave, label: Text(context.l10n.walletScreenToggleArweave)),
            ],
            selected: {_view},
            onSelectionChanged: (selection) => setState(() => _view = selection.first),
          ),
          const SizedBox(height: 12),

          if (_view == _WalletView.eth) ..._buildEthChildren(context) else ..._buildArweaveChildren(context),
        ],
      ),
    );
  }

  List<Widget> _buildEthChildren(BuildContext context) {
    var sessionCount = 0;
    var sessionCostWei = BigInt.zero;
    var deviceCount = 0;
    var deviceCostWei = BigInt.zero;
    for (final activity in _activities) {
      if (activity.type.name.startsWith('session')) {
        sessionCount++;
        sessionCostWei += activity.costWei;
      } else {
        deviceCount++;
        deviceCostWei += activity.costWei;
      }
    }

    final sortedActivities = _activities.reversed.toList();

    return [
          // ── Saldo + ações ────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.walletScreenBalanceLabel, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  if (_balanceLoading && _balanceWei == null)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      _balanceWei != null ? _formatEth(_balanceWei!) : '—',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _smartAccountAddress == null ? null : _showDepositSheet,
                          child: Text(context.l10n.walletScreenDepositButton),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              (_balanceWei == null || _balanceWei == BigInt.zero)
                                  ? null
                                  : _showWithdrawSheet,
                          child: Text(context.l10n.walletScreenWithdrawButton),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Custo por tipo ───────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.walletScreenCostByTypeTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _CostByTypeTile(label: context.l10n.walletScreenSessionsLabel, count: sessionCount, costWei: sessionCostWei, formatEth: _formatEth)),
                      Expanded(child: _CostByTypeTile(label: context.l10n.walletScreenDevicesLabel, count: deviceCount, costWei: deviceCostWei, formatEth: _formatEth)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Atividade ────────────────────────────────────────────────────
          Row(
            children: [
              Text(context.l10n.walletScreenActivityTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: _isScanning ? null : _rescan,
                child: Text(context.l10n.walletScreenRefreshButton, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (_isScanning && _activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _scanProgress != null
                    ? context.l10n.walletScreenScanningProgress(
                        _scanProgress!.scannedTo, _scanProgress!.latest)
                    : context.l10n.walletScreenScanningInProgress,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else if (_isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(context.l10n.walletScreenUpdating, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          if (_scanError != null)
            Card(
              color: AppColors.dangerBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.walletScreenActivityLoadError(_scanError!),
                        style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _rescan, child: Text(context.l10n.walletScreenRetryButton)),
                  ],
                ),
              ),
            )
          else if (!_isScanning && _activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(context.l10n.walletScreenNoActivity, style: const TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ...sortedActivities.map((activity) {
              final isRevoked = _revokedTypes.contains(activity.type);
              final shortHash = '${activity.hash.substring(0, 10)}...${activity.hash.substring(activity.hash.length - 6)}';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(
                            label: Text(_activityLabel(context, activity.type)),
                            backgroundColor: isRevoked ? AppColors.surfaceAlt : AppColors.successBg,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: isRevoked ? AppColors.textMuted : AppColors.success,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              shortHash,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDate(activity.timestamp)} · ${_formatEth(activity.costWei)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            }),
    ];
  }

  List<Widget> _buildArweaveChildren(BuildContext context) {
    if (_arweaveLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final balanceWinston = _arweaveBalanceWinston;
    final balanceAr = balanceWinston != null
        ? (double.parse(balanceWinston) / 1e12).toStringAsFixed(6)
        : null;

    return [
      // ── Wallet Arweave (endereço + saldo + gerar) ─────────────────────────
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.walletScreenArweaveIntro,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (_arweaveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_arweaveError!, style: const TextStyle(color: AppColors.danger)),
                ),
              if (!_arweaveExists)
                ElevatedButton(
                  onPressed: _arweaveGenerating ? null : _handleGenerateArweaveWallet,
                  child: Text(_arweaveGenerating
                      ? context.l10n.walletScreenArweaveGeneratingButton
                      : context.l10n.walletScreenArweaveGenerateButton),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      _arweaveAddress ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _handleCopyArweaveAddress,
                          icon: Icon(_arweaveCopied ? Icons.check : Icons.copy, size: 16),
                          label: Text(_arweaveCopied
                              ? context.l10n.walletScreenArweaveCopiedButton
                              : context.l10n.walletScreenArweaveCopyButton),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            balanceAr != null
                                ? context.l10n.walletScreenArweaveBalanceLabel(balanceAr)
                                : context.l10n.walletScreenArweaveBalanceUnavailable,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (balanceAr != null && double.parse(balanceAr) == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          context.l10n.walletScreenArweaveNoBalanceHint,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        context.l10n.walletScreenArweaveBackupWarning,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),

      if (_arweaveExists && _arweaveAddress != null) ...[
        const SizedBox(height: 12),
        // ── Histórico de transações ─────────────────────────────────────────
        Row(
          children: [
            Text(context.l10n.walletScreenArweaveHistoryTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () => _loadArweaveHistory(_arweaveAddress!),
              child: Text(context.l10n.walletScreenArweaveHistoryRefresh, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        if (_arweaveHistoryLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(context.l10n.walletScreenArweaveHistoryLoading,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
        if (_arweaveHistoryError != null && !_arweaveHistoryLoading)
          Card(
            color: AppColors.dangerBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.walletScreenArweaveHistoryFailedToLoad(_arweaveHistoryError!),
                      style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _loadArweaveHistory(_arweaveAddress!),
                    child: Text(context.l10n.walletScreenArweaveHistoryRetry),
                  ),
                ],
              ),
            ),
          ),
        if (!_arweaveHistoryLoading && _arweaveHistoryError == null && _arweaveHistory.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(context.l10n.walletScreenArweaveHistoryEmpty,
                  style: const TextStyle(color: AppColors.textMuted)),
            ),
          ),
        if (!_arweaveHistoryLoading && _arweaveHistoryError == null)
          ..._arweaveHistory.map((tx) {
            final idShort = '${tx.id.substring(0, 10)}...${tx.id.substring(tx.id.length - 6)}';
            final isTransfer = tx.quantityAr != '0';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Chip(
                          label: Text(isTransfer
                              ? context.l10n.walletScreenArweaveHistoryQuantity(tx.quantityAr)
                              : (tx.contentType ?? context.l10n.walletScreenArweaveHistoryDataTx)),
                          backgroundColor: AppColors.successBg,
                          labelStyle: const TextStyle(fontSize: 11, color: AppColors.success),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            idShort,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tx.blockTimestamp != null
                          ? '${_formatDate(tx.blockTimestamp!)} · ${context.l10n.walletScreenArweaveHistoryFee(tx.feeAr)}'
                          : '${context.l10n.walletScreenArweaveHistoryPending} · ${context.l10n.walletScreenArweaveHistoryFee(tx.feeAr)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    ];
  }
}

class _CostByTypeTile extends StatelessWidget {
  final String label;
  final int count;
  final BigInt costWei;
  final String Function(BigInt) formatEth;

  const _CostByTypeTile({
    required this.label,
    required this.count,
    required this.costWei,
    required this.formatEth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Text('$count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(formatEth(costWei), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

// ── Sheet de saque ────────────────────────────────────────────────────────

enum _WithdrawStep { form, submitting, done }

class _WithdrawSheet extends StatefulWidget {
  final BigInt availableBalanceWei;
  final Future<void> Function(EthereumAddress destination, BigInt amountWei) onSubmit;

  const _WithdrawSheet({required this.availableBalanceWei, required this.onSubmit});

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _destinationController = TextEditingController();
  final _amountController = TextEditingController();
  _WithdrawStep _step = _WithdrawStep.form;
  String? _error;

  @override
  void dispose() {
    _destinationController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  EthereumAddress? get _parsedDestination {
    try {
      final text = _destinationController.text.trim();
      if (text.isEmpty) return null;
      return EthereumAddress.fromHex(text);
    } catch (_) {
      return null;
    }
  }

  BigInt? get _parsedAmountWei => _parseEtherToWei(_amountController.text);

  bool get _canSubmit {
    final amount = _parsedAmountWei;
    return _step == _WithdrawStep.form &&
        _parsedDestination != null &&
        amount != null &&
        amount > BigInt.zero &&
        amount <= widget.availableBalanceWei;
  }

  void _setMax() {
    setState(() => _amountController.text = _weiToDecimalString(widget.availableBalanceWei));
  }

  Future<void> _submit() async {
    final destination = _parsedDestination;
    final amount = _parsedAmountWei;
    if (destination == null || amount == null) return;

    setState(() {
      _step = _WithdrawStep.submitting;
      _error = null;
    });

    try {
      await widget.onSubmit(destination, amount);
      if (mounted) setState(() => _step = _WithdrawStep.done);
    } catch (_) {
      if (mounted) {
        setState(() {
          _step = _WithdrawStep.form;
          _error = context.l10n.walletScreenWithdrawError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _WithdrawStep.done) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 56, color: AppColors.success),
            const SizedBox(height: 12),
            Text(context.l10n.walletScreenWithdrawSuccessTitle, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.l10n.walletScreenCloseButton),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.walletScreenWithdrawButton, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _destinationController,
            enabled: _step == _WithdrawStep.form,
            decoration: InputDecoration(labelText: context.l10n.walletScreenDestinationAddressLabel, hintText: '0x...'),
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  enabled: _step == _WithdrawStep.form,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: context.l10n.walletScreenAmountLabel, hintText: '0.0'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _step == _WithdrawStep.form ? _setMax : null,
                child: Text(context.l10n.walletScreenMaxButton),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.walletScreenAvailableBalance(_weiToDecimalString(widget.availableBalanceWei)),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(_step == _WithdrawStep.submitting ? context.l10n.walletScreenSubmittingButton : context.l10n.walletScreenWithdrawButton),
          ),
        ],
      ),
    );
  }
}

// Parseia um valor decimal de ETH (ex: "0.05") pra wei, sem depender de
// EtherAmount.fromBase10String — esse método do web3dart faz
// `BigInt.parse(amount)` puro sobre a string recebida (multiplicado pelo
// fator da unidade), ou seja NÃO entende ponto decimal, só inteiros na
// unidade dada. Retorna null pra entrada vazia, não-numérica, negativa ou
// com mais de 18 casas decimais (mais preciso que 1 wei — rejeitado em vez
// de truncado silenciosamente); a validação sintática (regex) fica aqui, o
// cálculo em si delega pra `eth_amount.parseEthToWei` (mesmo parsing
// decimal→wei usado em CreateIdentityScreen — achado de duplicação P82 #6).
BigInt? _parseEtherToWei(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) return null;
  try {
    return eth_amount.parseEthToWei(trimmed);
  } on FormatException {
    return null;
  }
}

// Inverso de _parseEtherToWei — usada pro botão "Max" pra que o valor
// preenchido sempre passe na validação de <= saldo disponível.
String _weiToDecimalString(BigInt wei) => eth_amount.weiToDecimalString(wei);

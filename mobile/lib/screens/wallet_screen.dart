import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web3dart/web3dart.dart';

import '../models/smart_account_activity.dart';
import '../services/activity_cache_service.dart';
import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/session_creator.dart';
import '../services/smart_account_activity_scanner.dart';
import '../theme.dart';

// Dashboard da smart account no mobile — porta de
// desktop/src/components/SmartAccountDashboard.tsx (14.10): saldo, resumo de
// custo por tipo de operação, histórico de atividade completo (desde o bloco
// de deploy dos contratos) e depósito/saque de ETH. Vive numa aba própria
// (ao contrário do saldo, que antes ficava dentro de SessionsScreen) pra
// espelhar a aba "dashboard" dedicada do Desktop.
class WalletScreen extends StatefulWidget {
  // Injetáveis para testes — em produção usa os defaults.
  final BlockchainService? blockchainService;
  final LocalStorageService? localStorageService;
  final DeviceKeyService? deviceKeyService;
  final BundlerConfigService? bundlerConfigService;
  final SessionCreator? sessionCreator;
  final SmartAccountActivityScanner? activityScanner;
  final ActivityCacheService? activityCacheService;

  const WalletScreen({
    super.key,
    this.blockchainService,
    this.localStorageService,
    this.deviceKeyService,
    this.bundlerConfigService,
    this.sessionCreator,
    this.activityScanner,
    this.activityCacheService,
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
  SessionCreator? _sessionCreator;

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

  static const _activityLabels = {
    SmartAccountActivityType.sessionCreated: 'Session created',
    SmartAccountActivityType.sessionRevoked: 'Session revoked',
    SmartAccountActivityType.sessionRevokedAll: 'All sessions revoked',
    SmartAccountActivityType.deviceRegistered: 'Device registered',
    SmartAccountActivityType.deviceRevoked: 'Device revoked',
  };

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
    _sessionCreator = widget.sessionCreator;
    _load();
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
              const Text('Deposit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Send ETH to your smart account address to fund future operations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                label: Text(copied ? 'Copied!' : 'Copy address'),
              ),
              const SizedBox(height: 10),
              const Text('Base Mainnet only',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
              const Text(
                'Device not paired',
                style: TextStyle(fontSize: 18, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pair this device with an identity to see your smart account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _pairedUsername != null ? '@$_pairedUsername' : 'Identity #$_pairedIdentityId',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // ── Saldo + ações ────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Balance', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
                          child: const Text('Deposit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              (_balanceWei == null || _balanceWei == BigInt.zero)
                                  ? null
                                  : _showWithdrawSheet,
                          child: const Text('Withdraw'),
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
                  const Text('Cost by type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _CostByTypeTile(label: 'Sessions', count: sessionCount, costWei: sessionCostWei, formatEth: _formatEth)),
                      Expanded(child: _CostByTypeTile(label: 'Devices', count: deviceCount, costWei: deviceCostWei, formatEth: _formatEth)),
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
              const Text('Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: _isScanning ? null : _rescan,
                child: const Text('Refresh', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (_isScanning && _activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _scanProgress != null
                    ? 'Scanning transaction history (block ${_scanProgress!.scannedTo} of ${_scanProgress!.latest})...'
                    : 'Scanning transaction history...',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Updating...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          if (_scanError != null)
            Card(
              color: AppColors.dangerBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Failed to load activity: $_scanError',
                        style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _rescan, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else if (!_isScanning && _activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No activity yet.', style: TextStyle(color: AppColors.textMuted)),
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
                            label: Text(_activityLabels[activity.type] ?? activity.type.name),
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
        ],
      ),
    );
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
          _error = 'Could not send the withdrawal. Make sure your account has enough ETH for gas.';
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
            const Text('Withdrawal sent!', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Close'),
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
          const Text('Withdraw', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _destinationController,
            enabled: _step == _WithdrawStep.form,
            decoration: const InputDecoration(labelText: 'Destination address', hintText: '0x...'),
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
                  decoration: const InputDecoration(labelText: 'Amount (ETH)', hintText: '0.0'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _step == _WithdrawStep.form ? _setMax : null,
                child: const Text('Max'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Available: ${_weiToDecimalString(widget.availableBalanceWei)} ETH',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(_step == _WithdrawStep.submitting ? 'Submitting...' : 'Withdraw'),
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
// unidade dada. Como o formulário aceita "0.05" ETH, o parse tem que ser
// manual: separa parte inteira/fracionária e preenche a fracionária até 18
// casas (wei). Retorna null pra entrada vazia, não-numérica, negativa ou com
// mais de 18 casas decimais (mais preciso que 1 wei — rejeitado em vez de
// truncado silenciosamente).
BigInt? _parseEtherToWei(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^(\d+)(\.(\d+))?$').firstMatch(trimmed);
  if (match == null) return null;

  final wholePart = match.group(1)!;
  final fracPart = match.group(3) ?? '';
  if (fracPart.length > 18) return null;

  final paddedFrac = fracPart.padRight(18, '0');
  final fracValue = paddedFrac.isEmpty ? BigInt.zero : BigInt.parse(paddedFrac);
  return BigInt.parse(wholePart) * BigInt.from(10).pow(18) + fracValue;
}

// Inverso de _parseEtherToWei — string decimal exata (sem o arredondamento
// de double de EtherAmount.getValueInUnit), usada pro botão "Max" pra que o
// valor preenchido sempre passe na validação de <= saldo disponível.
String _weiToDecimalString(BigInt wei) {
  final base = BigInt.from(10).pow(18);
  final whole = wei ~/ base;
  final frac = (wei % base).toString().padLeft(18, '0');
  final trimmedFrac = frac.replaceFirst(RegExp(r'0+$'), '');
  return trimmedFrac.isEmpty ? '$whole' : '$whole.$trimmedFrac';
}

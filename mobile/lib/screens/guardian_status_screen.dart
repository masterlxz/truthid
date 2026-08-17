import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../theme.dart';

// Tela de visualização do status de Social Recovery — apenas leitura.
// O Mobile nunca escreve no RecoveryManager (blockedForDevices na smart
// account). Toda operação de recovery (configurar guardians, propor,
// aprovar, executar, cancelar) é feita pelo Desktop com wallet (Ledger).
class GuardianStatusScreen extends StatefulWidget {
  const GuardianStatusScreen({super.key});

  @override
  State<GuardianStatusScreen> createState() => _GuardianStatusScreenState();
}

class _GuardianStatusScreenState extends State<GuardianStatusScreen> {
  final _blockchain = BlockchainService();
  final _storage = LocalStorageService();

  String? _username;
  List<String>? _guardians;
  BigInt? _threshold;
  RecoveryProposal? _proposal;
  BigInt? _timelock;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identityId = await _storage.getPairedIdentityId();
    String? username;
    if (identityId != null) {
      username = await resolvePairedUsername(
        storage: _storage,
        blockchain: _blockchain,
        identityId: identityId,
      );
    }

    if (username == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final results = await Future.wait([
      _blockchain.getGuardianConfig(username),
      _blockchain.getProposal(username),
      _blockchain.getTimelock(),
    ]);

    if (!mounted) return;
    setState(() {
      _username = username;
      _guardians = (results[0] as ({List<String> guardians, BigInt threshold})?)?.guardians;
      _threshold = (results[0] as ({List<String> guardians, BigInt threshold})?)?.threshold;
      _proposal = results[1] as RecoveryProposal?;
      _timelock = results[2] as BigInt?;
      _loading = false;
    });
  }

  String _timeRemaining(BigInt proposedAt) {
    const timelockSecs = Duration(days: 7);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deadline = proposedAt.toInt() + timelockSecs.inSeconds;
    if (now >= deadline) return context.l10n.guardianStatusScreenReadyToExecute;
    final diff = deadline - now;
    final d = diff ~/ 86400;
    final h = (diff % 86400) ~/ 3600;
    final m = (diff % 3600) ~/ 60;
    return context.l10n.guardianStatusScreenTimeRemaining(d, h, m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.guardianStatusScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _username == null
              ? Center(
                  child: Text(
                    context.l10n.guardianStatusScreenNoIdentity,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        context.l10n.guardianStatusScreenUsernameHandle(_username!),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.guardianStatusScreenSubtitle,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 24),

                      // ── Guardian configuration ──
                      if (_guardians == null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.guardianStatusScreenNoGuardiansWarning,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.people_outline,
                                      color: AppColors.accent, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.l10n.guardianStatusScreenGuardiansCount(
                                        (_threshold ?? '?').toString(), _guardians!.length),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SpaceGrotesk',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._guardians!.map((g) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.circle,
                                            size: 8,
                                            color: AppColors.textMuted),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${g.substring(0, 6)}…${g.substring(g.length - 4)}',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                              if (_timelock != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  context.l10n.guardianStatusScreenTimelockDays(
                                      (_timelock! ~/ BigInt.from(86400)).toString()),
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Active proposal ──
                      if (_proposal != null && !_proposal!.executed && !_proposal!.cancelled)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.warning, color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.l10n.guardianStatusScreenProposedTitle,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SpaceGrotesk',
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _propRow(context.l10n.guardianStatusScreenProposedByLabel, _proposal!.proposedBy),
                              _propRow(context.l10n.guardianStatusScreenNewControllerLabel, _proposal!.newController),
                              _propRow(
                                context.l10n.guardianStatusScreenApprovalsLabel,
                                context.l10n.guardianStatusScreenApprovalsValue(
                                    _proposal!.approvalCount.toString(), (_threshold ?? '?').toString()),
                              ),
                              _propRow(
                                context.l10n.guardianStatusScreenTimelockLabel,
                                _timeRemaining(_proposal!.proposedAt),
                              ),
                            ],
                          ),
                        ),

                      if (_proposal != null && _proposal!.executed)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppColors.success, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.guardianStatusScreenRecoveryExecuted,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_proposal != null && _proposal!.cancelled)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.textMuted.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.textMuted.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cancel, color: AppColors.textMuted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.guardianStatusScreenRecoveryCancelled,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.guardianStatusScreenDesktopOnlyFootnote,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.startsWith('0x')
                  ? '${value.substring(0, 8)}…${value.substring(value.length - 4)}'
                  : value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
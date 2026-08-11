import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/arweave_client.dart' show arweaveDefaultNode, getWalletBalance;
import '../services/arweave_wallet_service.dart';
import '../theme.dart';

// Wallet Arweave local usada pra publicar o vault — mirror de
// `ArweaveWalletSection` (desktop/src/components/VaultSettings.tsx:399-503),
// mesmo padrão de tela (StatefulWidget + setState) de pinning_providers_screen.dart.
class ArweaveWalletScreen extends StatefulWidget {
  final ArweaveWalletService? walletService;

  const ArweaveWalletScreen({super.key, this.walletService});

  @override
  State<ArweaveWalletScreen> createState() => _ArweaveWalletScreenState();
}

class _ArweaveWalletScreenState extends State<ArweaveWalletScreen> {
  late final ArweaveWalletService _walletService;

  bool _loading = true;
  bool _exists = false;
  String? _address;
  String? _balanceWinston;
  bool _generating = false;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _walletService = widget.walletService ?? ArweaveWalletService();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final exists = await _walletService.exists();
      if (!mounted) return;
      setState(() => _exists = exists);
      if (!exists) return;
      final address = await _walletService.address();
      if (!mounted) return;
      setState(() => _address = address);
      await _loadBalance(address);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Best-effort — uma wallet sem tráfego ainda deve aparecer com endereço
  // mesmo se a consulta de saldo falhar (mesmo comportamento do Desktop).
  Future<void> _loadBalance(String address) async {
    try {
      final balance = await getWalletBalance(arweaveDefaultNode, address);
      if (mounted) setState(() => _balanceWinston = balance);
    } catch (_) {
      if (mounted) setState(() => _balanceWinston = null);
    }
  }

  Future<void> _handleGenerate() async {
    setState(() { _error = null; _generating = true; });
    try {
      final address = await _walletService.generate();
      if (!mounted) return;
      setState(() { _address = address; _exists = true; });
      await _loadBalance(address);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _handleCopy() async {
    final address = _address;
    if (address == null) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final balanceWinston = _balanceWinston;
    final balanceAr = balanceWinston != null
        ? (double.parse(balanceWinston) / 1e12).toStringAsFixed(6)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet Arweave')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'O blob principal do vault é publicado no Arweave — precisa de uma '
                    'wallet local financiada com AR. (Documentos anexados continuam nos '
                    'providers de pinning.)',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                  if (!_exists)
                    ElevatedButton(
                      onPressed: _generating ? null : _handleGenerate,
                      child: Text(_generating ? 'Gerando...' : 'Gerar wallet Arweave'),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          _address ?? '',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _handleCopy,
                              icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                              label: Text(_copied ? '✓ Copiado!' : 'Copiar endereço'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                balanceAr != null
                                    ? 'Saldo: $balanceAr AR'
                                    : 'Saldo indisponível no momento',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (balanceAr != null && double.parse(balanceAr) == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Sem saldo ainda — compre AR numa exchange e envie pro '
                              'endereço acima antes de publicar.',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

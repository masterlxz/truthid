import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';

class DevicesScreen extends StatefulWidget {
  // Callback: chamado quando o usuário quer parear (abre o scanner no pai)
  final VoidCallback onScanPairing;

  const DevicesScreen({super.key, required this.onScanPairing});

  @override
  State<DevicesScreen> createState() => DevicesScreenState();
  //                                    ^ sem _ : precisa ser público para o GlobalKey funcionar
}

// Público (sem _) para que o RootScreen possa usar GlobalKey<DevicesScreenState>
class DevicesScreenState extends State<DevicesScreen> {
  final _keyService = DeviceKeyService();
  final _storage = LocalStorageService();

  String? _deviceAddress;
  ({String identityId, String username})? _pairedIdentity;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  // Público: chamado pelo RootScreen via GlobalKey após um pareamento bem-sucedido
  Future<void> reload() async {
    setState(() => _isLoading = true);

    final address = await _keyService.getDeviceAddress();
    final identity = await _storage.getPairedIdentity();

    if (!mounted) return;
    setState(() {
      _deviceAddress = address;
      _pairedIdentity = identity;
      _isLoading = false;
    });
  }

  void _copyAddress() {
    if (_deviceAddress == null) return;
    Clipboard.setData(ClipboardData(text: _deviceAddress!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Endereço copiado!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // RefreshIndicator: habilita o gesto "puxar pra baixo para atualizar"
    // Precisa de um filho que seja scrollável — usamos ListView
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Card do device ──────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho: ícone + título + chip de status
                  Row(
                    children: [
                      const Icon(Icons.phone_android),
                      const SizedBox(width: 8),
                      const Text(
                        'Este dispositivo',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      _pairedIdentity != null
                          ? Chip(
                              avatar: const Icon(Icons.verified, size: 14),
                              label: Text('@${_pairedIdentity!.username}'),
                              backgroundColor: Colors.green.shade100,
                              padding: EdgeInsets.zero,
                            )
                          : Chip(
                              label: const Text('Não registrado'),
                              backgroundColor: Colors.grey.shade200,
                            ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Endereço do device
                  const Text(
                    'Endereço',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _deviceAddress ?? '...',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: _copyAddress,
                        tooltip: 'Copiar endereço',
                      ),
                    ],
                  ),

                  // Seção de identidade — só aparece se estiver pareado
                  if (_pairedIdentity != null) ...[
                    const Divider(height: 24),
                    const Text(
                      'Identidade',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${_pairedIdentity!.username}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        await _storage.clearPairedIdentity();
                        reload();
                      },
                      icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
                      label: const Text(
                        'Remover pareamento',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Dica — só aparece se ainda não pareado ──────────────────────
          if (_pairedIdentity == null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Para registrar este dispositivo, gere um QR de pareamento '
                        'no app desktop e escaneie-o.',
                        style: TextStyle(fontSize: 13, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Botão de pareamento ──────────────────────────────────────────
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onScanPairing,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Parear com identidade'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

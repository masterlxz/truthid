import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import 'show_device_qr_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _keyService = DeviceKeyService();
  final _storage = LocalStorageService();

  String? _deviceAddress;
  String? _pairedIdentityId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);

    final address = await _keyService.getDeviceAddress();
    final identityId = await _storage.getPairedIdentityId();

    if (!mounted) return;
    setState(() {
      _deviceAddress = address;
      _pairedIdentityId = identityId;
      _isLoading = false;
    });
  }

  // Abre a tela que mostra o QR deste device. Quando ela fecha com
  // sucesso (o desktop terminou de registrar), recarrega esta tela pra
  // refletir o novo status — não precisa de GlobalKey: é a própria
  // DevicesScreen que inicia a navegação, então ela mesma recebe o resultado.
  Future<void> _openPairing() async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ShowDeviceQrScreen()),
    );
    if (success == true) _reload();
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
      onRefresh: _reload,
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
                      _pairedIdentityId != null
                          ? Chip(
                              avatar: const Icon(Icons.verified, size: 14),
                              label: Text('Identidade #$_pairedIdentityId'),
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
                  if (_pairedIdentityId != null) ...[
                    const Divider(height: 24),
                    const Text(
                      'Identidade',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#$_pairedIdentityId',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        await _storage.clearPairedIdentity();
                        _reload();
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
          if (_pairedIdentityId == null) ...[
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
                        'Toque no botão abaixo pra mostrar um QR com o '
                        'endereço deste device. Leia esse QR (ou cole o '
                        'endereço) no app desktop pra registrá-lo.',
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
              onPressed: _openPairing,
              icon: const Icon(Icons.qr_code),
              label: const Text('Mostrar QR para parear'),
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

import 'package:flutter/material.dart';
import 'screens/approval_screen.dart';
import 'screens/scan_screen.dart';
import 'services/device_key_service.dart';

void main() {
  runApp(const TruthIDApp());
}

class TruthIDApp extends StatelessWidget {
  const TruthIDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruthID',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const DeviceInfoScreen(),
    );
  }
}

class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  final _keyService = DeviceKeyService();
  String? _deviceAddress;

  @override
  void initState() {
    super.initState();
    _loadDeviceAddress();
  }

  Future<void> _loadDeviceAddress() async {
    final address = await _keyService.getDeviceAddress();
    setState(() => _deviceAddress = address);
  }

  Future<void> _openScanner() async {
    final payload = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (payload == null || !mounted) return;

    final action = payload['action'] as String?;

    if (action == 'truthid-auth') {
      // Pedido de login — abre a tela de aprovação
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ApprovalScreen(payload: payload),
        ),
      );
    } else {
      // QR desconhecido ou de outra ação (ex: truthid-pair)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR não reconhecido: ${action ?? "sem action"}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TruthID'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Endereço deste device:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            _deviceAddress == null
                ? const CircularProgressIndicator()
                : SelectableText(
                    _deviceAddress!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

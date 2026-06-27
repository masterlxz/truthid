import 'package:flutter/material.dart';
import 'screens/approval_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sessions_screen.dart';
import 'theme.dart';

void main() {
  runApp(const TruthIDApp());
}

class TruthIDApp extends StatelessWidget {
  const TruthIDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruthID',
      theme: appTheme,
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;

  // Único uso restante do scanner: ler o QR de login de um site (truthid-auth).
  // Pareamento de device não escaneia mais nada — ver ShowDeviceQrScreen.
  Future<void> _openScanner() async {
    final payload = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (payload == null || !mounted) return;

    final action = payload['action'] as String?;

    if (action == 'truthid-auth') {
      // QR de login — abre a tela de aprovação
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ApprovalScreen(payload: payload)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unrecognized QR: ${action ?? "no action"}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TruthID'),
        actions: [
          // Botão de scan no AppBar — acessível de qualquer aba
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openScanner,
            tooltip: 'Scan QR',
          ),
        ],
      ),

      // IndexedStack: mantém todas as telas na memória, mostra apenas a ativa.
      // Diferente de trocar o body, que destruiria e recriaria as telas.
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          DevicesScreen(),
          SessionsScreen(),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_android),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Sessions',
          ),
        ],
      ),
    );
  }
}


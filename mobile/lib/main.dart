import 'package:flutter/material.dart';
import 'screens/approval_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sessions_screen.dart';

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

  // GlobalKey: referência direta ao State do DevicesScreen.
  // Permite chamar devicesKey.currentState?.reload() de qualquer lugar aqui.
  final _devicesKey = GlobalKey<DevicesScreenState>();

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
    } else if (action == 'truthid-pair') {
      // QR de pareamento — abre PairingScreen e aguarda o resultado
      // push<bool> porque PairingScreen faz Navigator.pop(context, true/false)
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PairingScreen(payload: payload)),
      );
      // Se o pareamento foi confirmado, recarrega o DevicesScreen via GlobalKey
      if (success == true) {
        _devicesKey.currentState?.reload();
      }
    } else {
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
        actions: [
          // Botão de scan no AppBar — acessível de qualquer aba
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openScanner,
            tooltip: 'Escanear QR',
          ),
        ],
      ),

      // IndexedStack: mantém todas as telas na memória, mostra apenas a ativa.
      // Diferente de trocar o body, que destruiria e recriaria as telas.
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DevicesScreen(
            key: _devicesKey,
            onScanPairing: _openScanner,
          ),
          const SessionsScreen(),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_android),
            label: 'Dispositivos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Sessões',
          ),
        ],
      ),
    );
  }
}


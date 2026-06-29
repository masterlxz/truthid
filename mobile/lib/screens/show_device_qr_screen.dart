import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../theme.dart';

// Tela mostrada quando o usuário quer parear este celular com uma
// identidade. Diferente do fluxo antigo (escanear um QR do desktop e trocar
// mensagens por WebSocket), agora é o CELULAR que mostra o QR — ele é o
// único lado que já tem o dado que falta (o próprio endereço). O desktop lê
// esse QR (ou cola o endereço manualmente) e registra o device on-chain.
// Não existe troca de mensagem ao vivo: confirmamos que terminou só
// checando a blockchain periodicamente (polling).
class ShowDeviceQrScreen extends StatefulWidget {
  const ShowDeviceQrScreen({super.key});

  @override
  State<ShowDeviceQrScreen> createState() => _ShowDeviceQrScreenState();
}

class _ShowDeviceQrScreenState extends State<ShowDeviceQrScreen> {
  static const _label = 'TruthID Mobile';
  static const _pollInterval = Duration(seconds: 3);

  final _keyService = DeviceKeyService();
  final _blockchain = BlockchainService();
  final _storage = LocalStorageService();

  String? _address;
  Timer? _pollTimer;
  bool _confirmed = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final address = await _keyService.getDeviceAddress();
    if (!mounted) return;
    setState(() => _address = address);

    // Timer.periodic dispara o callback repetidamente até cancelarmos —
    // como um loop com sleep() entre as iterações, mas sem travar a UI.
    _pollTimer =
        Timer.periodic(_pollInterval, (_) => _checkIfRegistered(address));
  }

  Future<void> _checkIfRegistered(String address) async {
    if (_confirmed) return;
    if (mounted) setState(() => _isChecking = true);

    final device = await _blockchain.getDevice(address);

    if (device == null || device.revoked) {
      if (mounted) setState(() => _isChecking = false);
      return;
    }

    _pollTimer?.cancel();
    await _storage.savePairedIdentity(device.identityId.toString());

    // Fetch username in the background — don't block the confirmation UX.
    // If the RPC call fails, the app falls back to showing Identity #X.
    _blockchain.getUsernameForIdentity(device.identityId).then((username) {
      if (username != null) _storage.savePairedUsername(username);
    });

    if (!mounted) return;
    setState(() => _confirmed = true);

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String get _qrPayload => jsonEncode({
        'action': 'truthid-device',
        'pubKey': _address,
        'label': _label,
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair device'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _address == null
              ? const CircularProgressIndicator()
              : _confirmed
                  ? _buildConfirmedUI()
                  : _buildQrUI(),
        ),
      ),
    );
  }

  Widget _buildQrUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'On your computer, open "Add device" and scan this QR code '
          '(or paste the address below):',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Fundo branco explícito: o tema é dark, e um QR com módulos pretos
        // sobre um fundo quase preto (#0B0F14) ficaria ilegível pra câmera.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(data: _qrPayload, size: 220),
        ),
        const SizedBox(height: 24),
        SelectableText(
          _address!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        const SizedBox(height: 32),
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        const Text(
          'Waiting for the computer to register this device...',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _isChecking ? null : () => _checkIfRegistered(_address!),
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(_isChecking ? 'Checking...' : 'Check now'),
        ),
      ],
    );
  }

  Widget _buildConfirmedUI() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 72, color: AppColors.success),
        SizedBox(height: 16),
        Text('Paired successfully!', style: TextStyle(fontSize: 20)),
      ],
    );
  }
}

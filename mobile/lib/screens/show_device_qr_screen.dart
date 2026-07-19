import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/vault_key_service.dart';
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
  String? _encryptionPubKey;
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
    final encryptionPubKey = await _keyService.getDevicePublicKeyHex();
    if (!mounted) return;
    setState(() {
      _address = address;
      _encryptionPubKey = encryptionPubKey;
    });

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
    final identityId = device.identityId.toString();
    await _storage.savePairedIdentity(identityId);

    // Best-effort, não bloqueia a confirmação do pareamento — se falhar
    // aqui, as telas que precisam do username (Wallet, Sessions, Vault,
    // etc.) já tentam de novo sozinhas via este mesmo helper.
    unawaited(resolvePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
    ));

    // Non-critical: se falhar aqui (ex: app derrubado em background), a
    // VaultScreen oferece um retry que refaz este mesmo passo depois — os
    // dados cifrados já estão on-chain, não é preciso parear de novo.
    await VaultKeyService().tryRecoverFromChain(_blockchain);

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
        'encryptionKey': _encryptionPubKey,
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
          '(or paste the fields below — the Desktop app has no camera):',
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
        const Text(
          'Device address',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        SelectableText(
          _address!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        // Sem isto copiável aqui, o campo "Encryption key" do Desktop nunca
        // tinha como ser preenchido no caminho sem câmera (só colar) — o
        // pareamento "funcionava" (endereço + label), mas a vault key nunca
        // era cifrada/entregue, sempre em silêncio (encryptedVaultKey ficava
        // vazio pra sempre em on-chain, sem chance de corrigir depois: ver
        // DeviceRegistry.registerDevice, que reverte com
        // DeviceAlreadyRegistered numa 2a tentativa pro mesmo endereço).
        if (_encryptionPubKey != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Encryption key (needed to receive the Vault key)',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _encryptionPubKey!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
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

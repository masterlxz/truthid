import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';

enum _Status { connecting, sent, confirmed, error }

class PairingScreen extends StatefulWidget {
  // Payload do QR: { action, signalingUrl, roomId }
  final Map<String, dynamic> payload;

  const PairingScreen({super.key, required this.payload});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _keyService = DeviceKeyService();
  final _storage = LocalStorageService();

  WebSocket? _ws;
  _Status _status = _Status.connecting;
  String? _errorMessage;
  String? _confirmedUsername;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _ws?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final signalingUrl = widget.payload['signalingUrl'] as String?;
    final roomId = widget.payload['roomId'] as String?;

    if (signalingUrl == null || roomId == null) {
      setState(() {
        _status = _Status.error;
        _errorMessage = 'QR inválido: faltando signalingUrl ou roomId';
      });
      return;
    }

    try {
      // Conecta ao relay na sala criada pelo desktop
      final ws = await WebSocket.connect('$signalingUrl/rooms/$roomId');
      _ws = ws;

      // Busca o endereço deste device (chave pública derivada)
      final address = await _keyService.getDeviceAddress();

      // Envia o pedido de pareamento para o desktop
      ws.add(jsonEncode({
        'type': 'pair-request',
        'pubKey': address,
        'label': 'TruthID Mobile',
      }));

      if (mounted) setState(() => _status = _Status.sent);

      // Aguarda resposta do desktop (se ele mandar pair-confirmed)
      ws.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'pair-confirmed') {
              final username = msg['username'] as String?;
              final identityId = msg['identityId']?.toString();
              if (username != null && identityId != null) {
                _storage.savePairedIdentity(
                  username: username,
                  identityId: identityId,
                );
              }
              if (mounted) {
                setState(() {
                  _status = _Status.confirmed;
                  _confirmedUsername = username;
                });
              }
            }
          } catch (_) {
            // ignora mensagens malformadas
          }
        },
        onError: (_) {
          if (mounted && _status == _Status.connecting) {
            setState(() {
              _status = _Status.error;
              _errorMessage = 'Erro na conexão com o relay';
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parear dispositivo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          // switch como expressão: cada estado gera um widget diferente
          child: switch (_status) {
            _Status.connecting => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando ao servidor de sinalização...'),
                ],
              ),
            _Status.sent => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, size: 64, color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    'Pedido enviado!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Aguardando confirmação no app desktop...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 16),
                  LinearProgressIndicator(),
                ],
              ),
            _Status.confirmed => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Pareado com sucesso!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (_confirmedUsername != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '@$_confirmedUsername',
                      style: const TextStyle(fontSize: 16, color: Colors.green),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    // pop(true): avisa o pai que o pareamento foi bem-sucedido
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            _Status.error => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Erro ao conectar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Voltar'),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

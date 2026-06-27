import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/device_key_service.dart';

// Estados possíveis da tela — do início ao fim do fluxo de login
enum _Status {
  connecting,  // abrindo WebSocket com o servidor de sinalização
  waiting,     // aguardando o challenge chegar
  challenge,   // challenge recebido — mostrando UI de aprovar/recusar
  done,        // usuário respondeu — resposta enviada
  error,       // algo deu errado
}

class ApprovalScreen extends StatefulWidget {
  // payload vindo do QR: { action, signalingUrl, roomId }
  final Map<String, dynamic> payload;

  const ApprovalScreen({super.key, required this.payload});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  _Status _status = _Status.connecting;
  String _statusMsg = 'Conectando ao servidor...';
  Map<String, dynamic>? _challenge;
  bool _responded = false; // impede enviar duas respostas

  WebSocket? _ws;
  final _keyService = DeviceKeyService();

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

  // ── Passo 1: conectar ao servidor de sinalização ─────────────────────────────

  Future<void> _connect() async {
    final signalingUrl = widget.payload['signalingUrl'] as String;
    final roomId = widget.payload['roomId'] as String;

    // dart:io WebSocket — conexão persistente bidirecional.
    // Diferente de http.get (dispara e esquece), o WebSocket fica aberto
    // e recebe mensagens a qualquer momento — como um chat em tempo real.
    try {
      _ws = await WebSocket.connect('$signalingUrl/rooms/$roomId');
    } catch (_) {
      _setError('Não foi possível conectar ao servidor de sinalização.\n'
          'Verifique se ele está rodando e acessível na rede.');
      return;
    }

    // .listen() registra callbacks para mensagens, erros e fechamento.
    // É assíncrono — não bloqueia a UI, apenas "avisa" quando algo chegar.
    _ws!.listen(
      (data) => _handleMessage(jsonDecode(data as String) as Map<String, dynamic>),
      onError: (_) => _setError('Erro na conexão com o servidor.'),
      onDone: () {
        if (_status != _Status.done && _status != _Status.error) {
          _setError('O servidor fechou a conexão antes de finalizar.');
        }
      },
    );

    // Avisa o website que o mobile entrou na sala — ele vai enviar o challenge
    _wsSend({'type': 'ready'});
    _setStatus(_Status.waiting, 'Aguardando o site enviar o pedido de login...');
  }

  // ── Passo 2: receber o challenge pelo servidor de sinalização ────────────────

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'challenge') {
      setState(() {
        _challenge = msg;
        _status = _Status.challenge;
      });
    }
  }

  // ── Passo 3a: usuário aprova — assina com secp256k1 e envia de volta ─────────

  Future<void> _approve() async {
    if (_challenge == null || _responded) return;
    _responded = true;

    // Serializa o challenge exatamente como recebido.
    // O website vai verificar que: hash(conteúdo) bate com o challenge que ele enviou.
    final challengeJson = jsonEncode(_challenge);
    final signature = await _keyService.signChallenge(challengeJson);
    final deviceAddress = await _keyService.getDeviceAddress();

    _wsSend({
      'type': 'auth-response',
      'approved': true,
      'nonce': _challenge!['nonce'],
      'signature': signature,       // assinatura secp256k1 com prefixo Ethereum personal_sign
      'deviceAddress': deviceAddress, // endereço Ethereum — website verifica no DeviceRegistry
    });

    setState(() => _status = _Status.done);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Passo 3b: usuário recusa — envia rejeição sem assinar ────────────────────

  Future<void> _reject() async {
    if (_challenge == null || _responded) return;
    _responded = true;

    _wsSend({
      'type': 'auth-response',
      'approved': false,
      'nonce': _challenge!['nonce'],
    });

    setState(() => _status = _Status.done);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(false);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _wsSend(Map<String, dynamic> msg) => _ws?.add(jsonEncode(msg));

  void _setStatus(_Status s, String msg) {
    if (mounted) setState(() { _status = s; _statusMsg = msg; });
  }

  void _setError(String msg) {
    if (mounted) setState(() { _status = _Status.error; _statusMsg = msg; });
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedido de Login'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: switch (_status) {
        _Status.challenge => _buildChallengeUI(),
        _Status.done      => _buildDoneUI(),
        _Status.error     => _buildErrorUI(),
        _                 => _buildLoadingUI(),
      },
    );
  }

  Widget _buildLoadingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeUI() {
    final origin = _challenge!['origin'] as String? ?? 'site desconhecido';
    final issuedAt = _challenge!['issuedAt'] as int?;
    final time = issuedAt != null
        ? TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(issuedAt),
          ).format(context)
        : '—';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.lock_open_rounded, size: 64, color: Colors.indigo),
          const SizedBox(height: 16),
          const Text(
            'Pedido de login recebido',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Um site está pedindo para entrar com sua identidade TruthID.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          _InfoRow(label: 'Site', value: origin),
          const SizedBox(height: 8),
          _InfoRow(label: 'Hora', value: time),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _approve,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Aprovar', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reject,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Recusar', style: TextStyle(fontSize: 18)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade700),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDoneUI() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 72, color: Colors.green),
          SizedBox(height: 16),
          Text('Resposta enviada!', style: TextStyle(fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

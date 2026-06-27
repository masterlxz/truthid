import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/device_key_service.dart';

// Estados possíveis da tela — do início ao fim do fluxo de login
enum _Status {
  challenge,   // challenge lido do QR — mostrando UI de aprovar/recusar
  done,        // usuário respondeu — resposta enviada
  error,       // algo deu errado
}

class ApprovalScreen extends StatefulWidget {
  // payload vindo do QR: { action, challenge: {...}, callbackUrl }
  // O challenge já vem completo no QR — não precisamos de nenhuma rede pra
  // recebê-lo. Só a resposta assinada precisa viajar, direto pro callbackUrl
  // do próprio site (sem nenhum servidor do TruthID no meio).
  final Map<String, dynamic> payload;

  const ApprovalScreen({super.key, required this.payload});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  late _Status _status;
  String _statusMsg = '';
  Map<String, dynamic>? _challenge;
  String? _callbackUrl;
  bool _responded = false; // impede enviar duas respostas

  final _keyService = DeviceKeyService();

  @override
  void initState() {
    super.initState();

    final callbackUrl = widget.payload['callbackUrl'] as String?;
    final challenge = widget.payload['challenge'] as Map<String, dynamic>?;

    // https obrigatório: o mobile vai discar essa URL diretamente, então
    // ela precisa ser confiável — sem isso, um QR malicioso poderia apontar
    // pra um endpoint que intercepta a resposta assinada em texto claro.
    if (challenge == null || callbackUrl == null || !callbackUrl.startsWith('https://')) {
      _status = _Status.error;
      _statusMsg = 'QR inválido: challenge ausente ou callbackUrl não é https://.';
      return;
    }

    _challenge = challenge;
    _callbackUrl = callbackUrl;
    _status = _Status.challenge;
  }

  // ── Envia a resposta direto pro backend do site, via HTTPS ──────────────
  // Antes isso ia por um WebSocket com um servidor de sinalização do TruthID
  // no meio. Agora vai direto pro callbackUrl que o próprio site escolheu —
  // exatamente o endpoint /auth/verify que os exemplos do SDK já documentam.
  Future<void> _postResponse(Map<String, dynamic> response) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_callbackUrl!));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode(response));
      await request.close();
    } finally {
      client.close();
    }
  }

  // ── Usuário aprova — assina com secp256k1 e envia pro site ───────────────

  Future<void> _approve() async {
    if (_challenge == null || _responded) return;
    _responded = true;

    // Serializa o challenge exatamente como recebido.
    // O site vai verificar que: hash(conteúdo) bate com o challenge que ele criou.
    final challengeJson = jsonEncode(_challenge);
    final signature = await _keyService.signChallenge(challengeJson);
    final deviceAddress = await _keyService.getDeviceAddress();

    try {
      await _postResponse({
        'approved': true,
        'nonce': _challenge!['nonce'],
        'signature': signature,       // assinatura secp256k1 com prefixo Ethereum personal_sign
        'deviceAddress': deviceAddress, // endereço Ethereum — site verifica no DeviceRegistry
      });
    } catch (_) {
      _setError('Não foi possível enviar a resposta ao site. Verifique sua conexão.');
      return;
    }

    setState(() => _status = _Status.done);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Usuário recusa — envia rejeição sem assinar ───────────────────────────

  Future<void> _reject() async {
    if (_challenge == null || _responded) return;
    _responded = true;

    try {
      await _postResponse({
        'approved': false,
        'nonce': _challenge!['nonce'],
      });
    } catch (_) {
      // Recusa é best-effort: se o POST falhar, o challenge expira pelo TTL
      // no backend do site mesmo assim. Não vale travar o usuário aqui.
    }

    setState(() => _status = _Status.done);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(false);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _setError(String msg) {
    if (mounted) setState(() { _status = _Status.error; _statusMsg = msg; });
  }

  // ── UI ───────────────────────────────────────────────────────────────────

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
      },
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

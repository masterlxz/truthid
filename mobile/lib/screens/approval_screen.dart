import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import 'package:flutter/material.dart';

import '../services/device_key_service.dart';
import '../theme.dart';

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

  // Injetáveis para testes — em produção usa os defaults.
  final DeviceKeyService? keyService;
  final Future<void> Function(Map<String, dynamic>)? postResponse;

  const ApprovalScreen({
    super.key,
    required this.payload,
    this.keyService,
    this.postResponse,
  });

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  late _Status _status;
  String _statusMsg = '';
  Map<String, dynamic>? _challenge;
  String? _callbackUrl;
  bool _responded = false; // impede enviar duas respostas

  late final DeviceKeyService _keyService;

  @override
  void initState() {
    super.initState();
    _keyService = widget.keyService ?? DeviceKeyService();

    final callbackUrl = widget.payload['callbackUrl'] as String?;
    final challenge = widget.payload['challenge'] as Map<String, dynamic>?;

    // https obrigatório: o mobile vai discar essa URL diretamente, então
    // ela precisa ser confiável — sem isso, um QR malicioso poderia apontar
    // pra um endpoint que intercepta a resposta assinada em texto claro.
    if (challenge == null || callbackUrl == null || !callbackUrl.startsWith('https://')) {
      _status = _Status.error;
      _statusMsg = 'Invalid QR: missing challenge or callbackUrl is not https://.';
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
    if (widget.postResponse != null) {
      return widget.postResponse!(response);
    }
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

    final nonce = _challenge!['nonce'] as String;

    // 1. Assina o challenge JSON (autenticação — verificado pelo SDK no servidor)
    final challengeJson = jsonEncode(_challenge);
    final signature = await _keyService.signChallenge(challengeJson);
    final deviceAddress = await _keyService.getDeviceAddress();

    // 2. Assina o session hash (registro on-chain — verificado pelo SessionRegistry)
    // sessionHash = keccak256(utf8_bytes_do_nonce), igual ao que o servidor calcula
    final nonceBytes = Uint8List.fromList(utf8.encode(nonce));
    final sessionHash = keccak256(nonceBytes);
    final sessionSignature = await _keyService.signHash(sessionHash);

    try {
      await _postResponse({
        'approved': true,
        'nonce': nonce,
        'signature': signature,           // autenticação: personal_sign(JSON do challenge)
        'deviceAddress': deviceAddress,   // endereço Ethereum — verificado no DeviceRegistry
        'sessionSignature': sessionSignature, // registro on-chain: personal_sign(keccak256(nonce))
      });
    } catch (_) {
      _setError('Could not send response to the website. Check your connection.');
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
        title: const Text('Login Request'),
      ),
      body: switch (_status) {
        _Status.challenge => _buildChallengeUI(),
        _Status.done      => _buildDoneUI(),
        _Status.error     => _buildErrorUI(),
      },
    );
  }

  Widget _buildChallengeUI() {
    final origin = _challenge!['origin'] as String? ?? 'unknown site';
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
          const Icon(Icons.lock_open_rounded, size: 64, color: AppColors.accent),
          const SizedBox(height: 16),
          const Text(
            'Login request received',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'A website is requesting to sign in with your TruthID identity.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 32),
          _InfoRow(label: 'Site', value: origin),
          const SizedBox(height: 8),
          _InfoRow(label: 'Time', value: time),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _approve,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reject,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Reject', style: TextStyle(fontSize: 18)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
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
          Icon(Icons.check_circle, size: 72, color: AppColors.success),
          SizedBox(height: 16),
          Text('Response sent!', style: TextStyle(fontSize: 20)),
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
            const Icon(Icons.error_outline, size: 72, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
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
        color: AppColors.surfaceAlt,
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

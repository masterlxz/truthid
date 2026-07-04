import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:flutter/material.dart';

import '../config/secrets.dart';
import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/session_creator.dart';
import '../theme.dart';

// Estados possíveis da tela — do início ao fim do fluxo de login
enum _Status {
  challenge, // challenge lido do QR — mostrando UI de aprovar/recusar
  submitting, // aprovado — criando a sessão on-chain via UserOperation
  done, // sessão criada e site notificado
  error, // algo deu errado
}

class ApprovalScreen extends StatefulWidget {
  // payload vindo do QR: { action, challenge: {...}, callbackUrl }
  // O challenge já vem completo no QR — não precisamos de nenhuma rede pra
  // recebê-lo. Só a resposta assinada precisa viajar, direto pro callbackUrl
  // do próprio site (sem nenhum servidor do TruthID no meio).
  final Map<String, dynamic> payload;

  // Injetáveis para testes — em produção usa os defaults.
  final DeviceKeyService? keyService;
  final BlockchainService? blockchainService;
  final SessionCreator? sessionCreator;
  final LocalStorageService? localStorageService;
  final Future<void> Function(Map<String, dynamic>)? postResponse;

  const ApprovalScreen({
    super.key,
    required this.payload,
    this.keyService,
    this.blockchainService,
    this.sessionCreator,
    this.localStorageService,
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
  String? _identityId;
  String? _username;

  late final DeviceKeyService _keyService;
  late final BlockchainService _blockchainService;
  late final SessionCreator _sessionCreator;
  late final LocalStorageService _localStorageService;

  @override
  void initState() {
    super.initState();
    _keyService = widget.keyService ?? DeviceKeyService();
    _blockchainService = widget.blockchainService ?? BlockchainService();
    _localStorageService = widget.localStorageService ?? LocalStorageService();
    _sessionCreator =
        widget.sessionCreator ??
        SessionCreator(
          blockchainService: _blockchainService,
          deviceKeyService: _keyService,
          bundlerClient: PimlicoBundlerClient(
            bundlerUrl: pimlicoBundlerUrl(
              apiKey: pimlicoApiKey,
              network: 'base',
            ),
          ),
        );

    final callbackUrl = widget.payload['callbackUrl'] as String?;
    final challenge = widget.payload['challenge'] as Map<String, dynamic>?;

    // https obrigatório: o mobile vai discar essa URL diretamente, então
    // ela precisa ser confiável — sem isso, um QR malicioso poderia apontar
    // pra um endpoint que intercepta a resposta assinada em texto claro.
    if (challenge == null ||
        callbackUrl == null ||
        !callbackUrl.startsWith('https://')) {
      _status = _Status.error;
      _statusMsg =
          'Invalid QR: missing challenge or callbackUrl is not https://.';
      return;
    }

    _challenge = challenge;
    _callbackUrl = callbackUrl;
    _status = _Status.challenge;

    _localStorageService.getPairedIdentityId().then((id) {
      if (mounted) setState(() => _identityId = id);
    });
    _localStorageService.getPairedUsername().then((username) {
      if (mounted) setState(() => _username = username);
    });
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

    // 2. Assina o session hash — prova de posse exigida por SessionRegistry.createSession
    // sessionHash = keccak256(utf8_bytes_do_nonce), igual ao que o servidor calcula
    final nonceBytes = Uint8List.fromList(utf8.encode(nonce));
    final sessionHash = keccak256(nonceBytes);
    final sessionSignature = await _keyService.signHash(sessionHash);

    // O device precisa estar pareado com uma identidade — sem isso não há
    // smart account nem identityId pra registrar a sessão.
    if (_identityId == null || _username == null) {
      _setError('This device is not paired with any identity yet.');
      return;
    }

    setState(() => _status = _Status.submitting);

    // 3. Resolve a smart account (controller) da identidade on-chain.
    final identity = await _blockchainService.getIdentityByUsername(_username!);
    if (identity == null) {
      _setError(
        'Could not find this identity on-chain. Check your connection.',
      );
      return;
    }

    // 4. Cria a sessão on-chain via UserOperation (etapa 14.9.5) — o próprio
    // device monta, assina e envia a UserOp; a smart account paga o gas.
    // Substitui o relayer server-side que o SDK usava até aqui (débito a
    // resolver no SDK na 14.9.6, pra não chamar createSession de novo lá).
    try {
      await _sessionCreator.createSession(
        identityId: identity.id,
        smartAccountAddress: identity.controller,
        sessionHash: sessionHash,
        devicePubKey: EthereumAddress.fromHex(deviceAddress),
        sessionSignatureHex: sessionSignature,
      );
    } catch (_) {
      _setError(
        'Could not create the session on-chain. Make sure your account has enough ETH for gas.',
      );
      return;
    }

    // 5. Notifica o site — o POST em si não muda desde antes da 14.9.5; o
    // que muda é que a sessão já existe on-chain quando ele chega.
    try {
      await _postResponse({
        'approved': true,
        'nonce': nonce,
        'signature':
            signature, // autenticação: personal_sign(JSON do challenge)
        'deviceAddress':
            deviceAddress, // endereço Ethereum — verificado no DeviceRegistry
        'sessionSignature':
            sessionSignature, // personal_sign(keccak256(nonce)) — já registrado on-chain
      });
    } catch (_) {
      _setError(
        'Could not send response to the website. Check your connection.',
      );
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
      await _postResponse({'approved': false, 'nonce': _challenge!['nonce']});
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
    if (mounted) {
      setState(() {
        _status = _Status.error;
        _statusMsg = msg;
      });
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Request')),
      body: switch (_status) {
        _Status.challenge => _buildChallengeUI(),
        _Status.submitting => _buildSubmittingUI(),
        _Status.done => _buildDoneUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildChallengeUI() {
    final uri = Uri.tryParse(_callbackUrl ?? '');
    final displaySite = uri != null
        ? '${uri.scheme}://${uri.host}'
        : (_challenge!['origin'] as String? ?? 'unknown site');
    final issuedAt = _challenge!['issuedAt'] as int?;
    final time = issuedAt != null
        ? TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(issuedAt),
          ).format(context)
        : '—';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(
              Icons.lock_open_rounded,
              size: 64,
              color: AppColors.accent,
            ),
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
            _InfoRow(label: 'Site', value: displaySite),
            const SizedBox(height: 8),
            _InfoRow(label: 'Time', value: time),
            if (_identityId != null) ...[
              const SizedBox(height: 8),
              _InfoRow(label: 'Signing as', value: 'Identity #$_identityId'),
            ],
            const SizedBox(height: 32),
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
      ),
    );
  }

  Widget _buildSubmittingUI() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Creating your session on-chain...'),
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
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
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

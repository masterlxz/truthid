import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../services/blockchain_service.dart';
import '../services/bundler_config_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../services/pimlico_bundler_client.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/session_creator.dart';
import '../services/vault_edit_content_cipher_service.dart';
import '../services/vault_lan_server_service.dart';
import '../services/vault_publish_service.dart';
import '../services/vault_repository.dart';
import '../theme.dart';

// Diferente do irmão `PinApprovalScreen`, aqui não há fase 2 de entrega de
// resultado — a extensão não roda servidor, não tem como receber um "sent"
// de volta (ver PROJECT_STATE.md, "fora de escopo"). No approve, o celular
// persiste a entrada e publica sozinho; `publishing` cobre as duas etapas
// (pin no IPFS + assinatura de UserOperation).
enum _Status {
  receivingContent,
  awaitingApproval,
  publishing,
  done,
  timeout,
  error,
}

/// Tela de aprovação de `/truthid/v1/vault-edit` cross-device (Sessão 134,
/// item 6 do roadmap) — a extensão de navegador propõe uma credencial nova
/// (só passkey nesta rodada; senha nova via extensão fica pra um item
/// futuro do backlog) e o celular decide se persiste e publica. Mirror
/// estrutural de `PinApprovalScreen`: mesma fase 1 (receber o conteúdo via
/// `RemoteSignerLanServer.receiveOnce`, decifrar com uma chave simétrica
/// derivada do `sessionId`), mas com dois desvios reais:
///   1. Sem fase de retorno — a extensão só faz HTTP client, não sobe
///      servidor, então não há pra onde entregar um resultado. A extensão
///      considera a proposta "enviada" assim que o PUT retorna 200, sem
///      esperar confirmação de publicação (best-effort).
///   2. No approve, o conteúdo recebido JÁ é a proposta de entrada em si
///      (não algo genérico a repassar) — persiste via `VaultRepository.
///      addEntry` e publica via `VaultPublishService.publish`, precisando
///      antes resolver a smart account pareada neste celular (o QR nunca
///      traz `smartAccountAddress`, mesma postura de `SignRequestApprovalScreen`).
///
/// Schema do QR v1 (`truthid-vault-edit`, mesmos 5 campos do `truthid-pin`):
///   { action: 'truthid-vault-edit', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName }
/// Espelha `extension/src/session/qrPayload.ts::buildVaultEditQrPayload` e
/// `extension/src/vaultEdit/cipher.ts` (mesmo salt/info em
/// `vault_edit_content_cipher_service.dart`, domain separation do `/pin`).
class VaultEditApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final RemoteSignerLanServer? lanServer;
  final VaultRepository? repository;
  final LocalStorageService? localStorageService;
  final BlockchainService? blockchainService;
  final BundlerConfigService? bundlerConfigService;
  final VaultPublishService? publishService;

  const VaultEditApprovalScreen({
    super.key,
    required this.payload,
    this.lanServer,
    this.repository,
    this.localStorageService,
    this.blockchainService,
    this.bundlerConfigService,
    this.publishService,
  });

  @override
  State<VaultEditApprovalScreen> createState() =>
      _VaultEditApprovalScreenState();
}

class _VaultEditApprovalScreenState extends State<VaultEditApprovalScreen> {
  late _Status _status;
  String? _sessionId;
  DateTime? _expiresAt;
  String? _appName;
  Map<String, dynamic>? _proposal;
  String? _errorMsg;
  List<String> _localIps = [];
  bool _showPassword = false;
  // Guarda "Try again" (achado real, Sessão 135) de recriar a entrada no
  // vault a cada retry — se addEntry já teve sucesso numa tentativa
  // anterior e só publish() falhou depois, retentar não deve chamar
  // addEntry de novo (criaria uma 2ª entrada duplicada pro mesmo site).
  bool _entryPersisted = false;

  late final RemoteSignerLanServer _lanServer;
  late final VaultRepository _repository;
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final BundlerConfigService _bundlerConfigService;
  VaultPublishService? _publishService;

  @override
  void initState() {
    super.initState();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();
    _repository = widget.repository ?? VaultRepository();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _bundlerConfigService =
        widget.bundlerConfigService ?? BundlerConfigService();
    _publishService = widget.publishService;

    final validationError = _validatePayload();
    if (validationError != null) {
      _status = validationError;
      return;
    }
    _status = _Status.receivingContent;
    unawaited(_receiveContent());
  }

  _Status? _validatePayload() {
    final v = widget.payload['v'];
    if (v != 1) {
      _errorMsg = 'Invalid QR: unsupported schema version.';
      return _Status.error;
    }

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMsg = 'Invalid QR: missing sessionId.';
      return _Status.error;
    }

    final ephemeralPubKey = widget.payload['ephemeralPubKey'] as String?;
    if (ephemeralPubKey == null || ephemeralPubKey.isEmpty) {
      _errorMsg = 'Invalid QR: missing ephemeralPubKey.';
      return _Status.error;
    }

    final expiresAtMs = widget.payload['expiresAt'];
    if (expiresAtMs is! int) {
      _errorMsg = 'Invalid QR: missing expiresAt.';
      return _Status.error;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      _errorMsg = 'This QR code has expired — go back to the extension and '
          'scan a fresh one.';
      return _Status.error;
    }

    final appName = (widget.payload['appName'] as String?)?.trim() ?? '';
    if (appName.isEmpty) {
      _errorMsg = 'Invalid QR: missing appName.';
      return _Status.error;
    }

    _sessionId = sessionId;
    _expiresAt = expiresAt;
    _appName = appName;
    return null;
  }

  Future<void> _receiveContent() async {
    unawaited(
      VaultLanServerService.getLocalIpAddresses()
          .then<void>((ips) {
            if (!mounted) return;
            setState(() => _localIps = ips);
          })
          .catchError((_) {}),
    );

    final encrypted = await _lanServer.receiveOnce(
      sessionId: _sessionId!,
      expiresAt: _expiresAt!,
    );
    if (!mounted) return;

    if (encrypted == null) {
      setState(() => _status = _Status.timeout);
      return;
    }

    try {
      final key = deriveVaultEditContentKey(_sessionId!);
      final content = await decryptVaultEditContent(encrypted, key);
      final proposal =
          jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _status = _Status.awaitingApproval;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to decrypt the received proposal: $e';
      });
    }
  }

  Future<EthereumAddress?> _resolveSmartAccountAddress() async {
    final identityId = await _storage.getPairedIdentityId();
    if (identityId == null) {
      if (!mounted) return null;
      setState(() {
        _status = _Status.error;
        _errorMsg = "This phone isn't paired with a TruthID identity yet.";
      });
      return null;
    }

    // O celular já está pareado (identityId persistido), mas o username
    // pode nunca ter resolvido (achado real, Sessão 134/135). Tenta de novo
    // aqui antes de desistir, em vez de reportar "não pareado" (engana o
    // usuário a re-parear em vez de só esperar o on-chain resolver).
    // `resolvePairedUsername` é o mesmo helper que wallet_screen.dart usa —
    // extraído como compartilhado depois de aparecer duplicado nos dois.
    final username = await resolvePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
    );
    if (username == null) {
      if (!mounted) return null;
      setState(() {
        _status = _Status.error;
        _errorMsg =
            'Still resolving your identity on-chain — try again in a moment.';
      });
      return null;
    }

    // Guardado explicitamente (achado real, Sessão 135/ultrareview): sem
    // isso, uma falha aqui (ex: RPC fora do ar) caía no catch genérico de
    // _approve() e mostrava uma mensagem de erro crua em vez desta,
    // consistente com o branch "identity == null" logo abaixo.
    IdentityInfo? identity;
    try {
      identity = await _blockchain.getIdentityByUsername(username);
    } catch (_) {
      identity = null;
    }
    if (identity == null) {
      if (!mounted) return null;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Could not resolve your smart account — try again.';
      });
      return null;
    }
    return identity.controller;
  }

  Future<VaultPublishService> _ensurePublishService() async {
    final existing = _publishService;
    if (existing != null) return existing;

    final bundlerConfig = await _bundlerConfigService.getConfig();
    final sessionCreator = SessionCreator(
      bundlerClient: PimlicoBundlerClient(
        bundlerUrl: pimlicoBundlerUrl(
          apiKey: bundlerConfig.apiKey,
          network: bundlerConfig.network,
        ),
      ),
    );
    final created = VaultPublishService(
      sessionCreator: sessionCreator,
      repository: _repository,
    );
    _publishService = created;
    return created;
  }

  Future<void> _approve() async {
    setState(() => _status = _Status.publishing);

    try {
      final smartAccountAddress = await _resolveSmartAccountAddress();
      if (smartAccountAddress == null) return; // erro já setado acima

      if (!_entryPersisted) {
        final proposal = _proposal!;
        final passkeyJson = proposal['passkey'] as Map<String, dynamic>?;
        await _repository.addEntry(
          site: proposal['site'] as String? ?? '',
          url: proposal['url'] as String? ?? '',
          username: proposal['username'] as String? ?? '',
          password: proposal['password'] as String? ?? '',
          notes: proposal['notes'] as String? ?? '',
          passkey: passkeyJson != null ? Passkey.fromJson(passkeyJson) : null,
        );
        _entryPersisted = true;
      }

      final publishService = await _ensurePublishService();
      await publishService.publish(smartAccountAddress);

      if (!mounted) return;
      setState(() => _status = _Status.done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to save and publish the new credential: $e';
      });
    }
  }

  void _reject() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New credential request')),
      body: switch (_status) {
        _Status.receivingContent => _buildReceivingUI(),
        _Status.awaitingApproval => _buildApprovalUI(),
        _Status.publishing => _buildPublishingUI(),
        _Status.done => _buildDoneUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildReceivingUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            Text(
              '${_appName ?? 'An app'} wants to send a new credential...',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure your phone and computer are on the same Wi-Fi '
              'network.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            if (_localIps.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'If the extension can\'t find your phone automatically, '
                'enter this IP address manually:',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              ..._localIps.map(
                (ip) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    ip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalUI() {
    final proposal = _proposal!;
    final site = proposal['site'] as String? ?? '';
    final username = proposal['username'] as String? ?? '';
    final password = proposal['password'] as String? ?? '';
    final hasPasskey = proposal['passkey'] != null;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Icon(Icons.key_outlined, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              '$_appName wants to save a new credential',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Site', style: const TextStyle(color: AppColors.textMuted)),
                    Text(site, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    Text('Username', style: const TextStyle(color: AppColors.textMuted)),
                    Text(username, style: const TextStyle(fontSize: 16)),
                    if (password.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Password', style: const TextStyle(color: AppColors.textMuted)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _showPassword ? password : '•' * password.length,
                            style: const TextStyle(fontSize: 16),
                          ),
                          IconButton(
                            icon: Icon(_showPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ],
                      ),
                    ],
                    if (hasPasskey) ...[
                      const SizedBox(height: 12),
                      const Chip(label: Text('+ passkey')),
                    ],
                  ],
                ),
              ),
            ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildPublishingUI() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildDoneUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              'Saved',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The new credential was saved to your vault and published.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 72, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Nothing arrived',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The extension never connected before this request expired. '
              'Make sure both devices are on the same Wi-Fi network and try '
              'again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
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

  Widget _buildErrorUI() {
    // Achado real (Sessão 135): se o conteúdo já chegou e foi decifrado
    // (_proposal != null), o erro aconteceu durante o approve (ex: RPC
    // falhou ao resolver a smart account) — a proposta já decifrada
    // continua em memória, não precisa de um QR novo pra tentar de novo.
    // "Back" descartava ela pra sempre mesmo quando o retry era trivial.
    // Erros de validação do QR ou de decrypt (_proposal ainda null) não têm
    // o que retentar — só "Back" faz sentido nesses.
    final canRetry = _proposal != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (canRetry) ...[
              ElevatedButton(
                onPressed: _approve,
                child: const Text('Try again'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

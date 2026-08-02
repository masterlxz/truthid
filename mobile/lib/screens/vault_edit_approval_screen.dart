import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import '../services/vault_edit_dead_drop_polling_service.dart';
import '../services/vault_lan_server_service.dart';
import '../services/vault_publish_service.dart';
import '../services/vault_repository.dart';
import '../theme.dart';

// Diferente do irmão `PinApprovalScreen`, aqui não há fase 2 de entrega de
// resultado — a extensão não roda servidor, não tem como receber um "sent"
// de volta (ver project/INDEX.md, "fora de escopo"). No approve, o celular
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
/// item 6 do roadmap) — a extensão de navegador propõe 1+ credenciais novas
/// (senha e/ou passkey — sync em lote desde o P29, Sessão 166) e o celular
/// decide se persiste e publica. Mirror estrutural de `PinApprovalScreen`:
/// mesma fase 1 (receber o conteúdo via `RemoteSignerLanServer.receiveOnce`,
/// decifrar com uma chave simétrica derivada do `sessionId`), mas com dois
/// desvios reais:
///   1. Sem fase de retorno — a extensão só faz HTTP client, não sobe
///      servidor, então não há pra onde entregar um resultado. A extensão
///      considera a proposta "enviada" assim que o PUT retorna 200, sem
///      esperar confirmação de publicação (best-effort).
///   2. No approve, o conteúdo recebido JÁ é a lista de propostas de entrada
///      em si (não algo genérico a repassar) — persiste cada uma via
///      `VaultRepository.addEntry` e publica **uma vez só**, no fim, via
///      `VaultPublishService.publish` (1 pin no IPFS + 1 UserOperation pra
///      N entradas — `VaultRegistry.updateVault` sempre grava um único
///      `(cid, contentHash)` por publish, não importa quantas mudaram no
///      blob, então não precisa de `executeBatch`/multi-call nenhum),
///      precisando antes resolver a smart account pareada neste celular (o
///      QR nunca traz `smartAccountAddress`, mesma postura de
///      `SignRequestApprovalScreen`).
///
/// Schema do QR v1 (`truthid-vault-edit`, mesmos 5 campos do `truthid-pin`):
///   { action: 'truthid-vault-edit', v: 1, sessionId, ephemeralPubKey,
///     expiresAt, appName }
/// Espelha `extension/src/session/qrPayload.ts::buildVaultEditQrPayload` e
/// `extension/src/vaultEdit/cipher.ts` (mesmo salt/info em
/// `vault_edit_content_cipher_service.dart`, domain separation do `/pin`).
/// O conteúdo cifrado em si é uma lista de propostas desde o P29 — mas o
/// SDK Dart (`TruthIDRequester.vaultEdit`) ainda manda um objeto único por
/// sessão, então `_receiveContent` aceita os dois formatos (ver comentário
/// lá) sem exigir nenhuma mudança no SDK já lançado.
class VaultEditApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final RemoteSignerLanServer? lanServer;
  final VaultRepository? repository;
  final LocalStorageService? localStorageService;
  final BlockchainService? blockchainService;
  final BundlerConfigService? bundlerConfigService;
  final VaultPublishService? publishService;
  final VaultEditDeadDropPollingService? deadDropPollingService;

  const VaultEditApprovalScreen({
    super.key,
    required this.payload,
    this.lanServer,
    this.repository,
    this.localStorageService,
    this.blockchainService,
    this.bundlerConfigService,
    this.publishService,
    this.deadDropPollingService,
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
  // Sync em lote (P29): uma sessão cobre 1+ propostas — o conteúdo cifrado
  // recebido pode ser tanto uma lista (extensão, depois do P29) quanto um
  // objeto único (SDK Dart's TruthIDRequester.vaultEdit, ainda manda uma
  // proposta por sessão — ver _receiveContent). Normalizado pra lista sempre.
  List<Map<String, dynamic>>? _proposals;
  String? _errorMsg;
  List<String> _localIps = [];
  final Set<int> _visiblePasswords = {};
  // Guarda "Try again" (achado real, Sessão 135) de recriar entradas no
  // vault a cada retry — índices de _proposals já persistidos via addEntry
  // numa tentativa anterior não são recriados se só publish() falhou depois
  // (criaria entradas duplicadas pro mesmo site).
  final Set<int> _persistedIndices = {};
  // Guarda transiente contra reentrância (duplo toque) — diferente de
  // _entryPersisted, que só protege contra duplicar a entrada num retry
  // SEQUENCIAL depois de falha. Essa aqui é resetada a cada tentativa
  // (finally), pra não quebrar o "Try again" legítimo.
  bool _approving = false;

  late final RemoteSignerLanServer _lanServer;
  late final VaultRepository _repository;
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;
  late final BundlerConfigService _bundlerConfigService;
  late final VaultEditDeadDropPollingService _deadDropPollingService;
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
    _deadDropPollingService =
        widget.deadDropPollingService ?? VaultEditDeadDropPollingService();
    _publishService = widget.publishService;

    final validationError = _validatePayload();
    if (validationError != null) {
      _status = validationError;
      return;
    }
    _status = _Status.receivingContent;
    unawaited(_receiveContent());
  }

  // Achado #7 do /code-review (Sessão 140): sem isto, o canal perdedor da
  // corrida LAN vs dead-drop (_receiveViaAnyChannel) continuava rodando
  // depois da tela fechar — se o dead-drop vencesse, o listener LAN ficava
  // ligado (porta ocupada) até seu próprio timeout; se a LAN vencesse, o
  // `pollUntil` do dead-drop continuava batendo no gateway público a cada
  // ~15s pelo TTL da sessão inteiro. `_disposed` corta o polling do
  // dead-drop na próxima checagem; `_lanServer.stop()` libera a porta na
  // hora (não cancela o `Future` pendente de `receiveOnce` em si — ele seria
  // resolvido pelo próprio timeout interno de qualquer forma — mas devolve
  // a porta pro sistema, que é o efeito colateral real observado no achado
  // #3: 5 portas candidatas presas por telas antigas nunca liberadas).
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_lanServer.stop());
    super.dispose();
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

    final encrypted = await _receiveViaAnyChannel();
    if (!mounted) return;

    if (encrypted == null) {
      setState(() => _status = _Status.timeout);
      return;
    }

    try {
      final key = deriveVaultEditContentKey(_sessionId!);
      final content = await decryptVaultEditContent(encrypted, key);
      final decoded = jsonDecode(utf8.decode(content));
      // A extensão manda uma lista desde o P29 (sync em lote); o SDK Dart's
      // TruthIDRequester.vaultEdit ainda manda um objeto único por sessão —
      // aceita os dois formatos sem exigir nenhuma mudança no SDK já lançado.
      final proposals = decoded is List
          ? decoded.cast<Map<String, dynamic>>()
          : [decoded as Map<String, dynamic>];
      if (!mounted) return;
      setState(() {
        _proposals = proposals;
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

  // Corrida entre os dois canais de entrega da proposta cifrada (item 6 do
  // backlog, dead-drop cross-network): LAN (`_lanServer.receiveOnce`,
  // depende de estar na mesma rede que o PC — e, achado da Sessão 136, do
  // celular ficar em primeiro plano) e dead-drop
  // (`_deadDropPollingService.pollUntil`, GET público, funciona cross-
  // network e mesmo em background). Resolve com o primeiro resultado
  // não-nulo; se os dois derem `null` (timeout dos dois lados), devolve
  // `null` — mesmo contrato que `_lanServer.receiveOnce` tinha sozinho.
  Future<Uint8List?> _receiveViaAnyChannel() async {
    final completer = Completer<Uint8List?>();
    var pending = 2;

    void handle(Uint8List? result) {
      if (completer.isCompleted) return;
      if (result != null) {
        completer.complete(result);
        return;
      }
      pending--;
      if (pending == 0) completer.complete(null);
    }

    // Achado #3 do /code-review (Sessão 140): sem `.catchError`, uma exceção
    // de qualquer um dos dois lados (ex: `StateError` do `_lanServer` quando
    // as 5 portas candidatas já estão todas ligadas por outra tela) nunca
    // chamava `handle` — `pending` ficava travado em 1 pra sempre e, se o
    // outro canal também desse `null`, `completer.future` nunca resolvia
    // (spinner "receiving" infinito, sem erro visível). Trata uma exceção
    // igual a um resultado `null` — "esse canal não entregou", mesmo
    // contrato de um timeout limpo.
    unawaited(
      _lanServer
          .receiveOnce(sessionId: _sessionId!, expiresAt: _expiresAt!)
          .then(handle)
          .catchError((_) => handle(null)),
    );
    unawaited(
      _deadDropPollingService
          .pollUntil(_sessionId!, _expiresAt!, isCancelled: () => _disposed)
          .then(handle)
          .catchError((_) => handle(null)),
    );

    return completer.future;
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
    if (_approving) return;
    _approving = true;
    setState(() => _status = _Status.publishing);

    try {
      final smartAccountAddress = await _resolveSmartAccountAddress();
      if (smartAccountAddress == null) return; // erro já setado acima

      final proposals = _proposals!;
      for (var i = 0; i < proposals.length; i++) {
        if (_persistedIndices.contains(i)) continue;
        final proposal = proposals[i];
        final passkeyJson = proposal['passkey'] as Map<String, dynamic>?;
        await _repository.addEntry(
          site: proposal['site'] as String? ?? '',
          url: proposal['url'] as String? ?? '',
          username: proposal['username'] as String? ?? '',
          password: proposal['password'] as String? ?? '',
          notes: proposal['notes'] as String? ?? '',
          passkey: passkeyJson != null ? Passkey.fromJson(passkeyJson) : null,
        );
        _persistedIndices.add(i);
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
    } finally {
      _approving = false;
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

  Widget _buildProposalCard(int index, Map<String, dynamic> proposal) {
    final site = proposal['site'] as String? ?? '';
    final username = proposal['username'] as String? ?? '';
    final password = proposal['password'] as String? ?? '';
    final hasPasskey = proposal['passkey'] != null;
    final showPassword = _visiblePasswords.contains(index);

    return Card(
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
                    showPassword ? password : '•' * password.length,
                    style: const TextStyle(fontSize: 16),
                  ),
                  IconButton(
                    icon: Icon(showPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(() {
                      if (showPassword) {
                        _visiblePasswords.remove(index);
                      } else {
                        _visiblePasswords.add(index);
                      }
                    }),
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
    );
  }

  Widget _buildApprovalUI() {
    final proposals = _proposals!;
    final title = proposals.length == 1
        ? '$_appName wants to save a new credential'
        : '$_appName wants to save ${proposals.length} new credentials';

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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < proposals.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildProposalCard(i, proposals[i]),
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
          ],
        ),
      ),
    );
  }

  Widget _buildPublishingUI() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildDoneUI() {
    final count = _proposals?.length ?? 1;
    final message = count == 1
        ? 'The new credential was saved to your vault and published.'
        : 'The $count new credentials were saved to your vault and published.';
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
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
    // (_proposals != null), o erro aconteceu durante o approve (ex: RPC
    // falhou ao resolver a smart account) — a proposta já decifrada
    // continua em memória, não precisa de um QR novo pra tentar de novo.
    // "Back" descartava ela pra sempre mesmo quando o retry era trivial.
    // Erros de validação do QR ou de decrypt (_proposals ainda null) não têm
    // o que retentar — só "Back" faz sentido nesses.
    final canRetry = _proposals != null;
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

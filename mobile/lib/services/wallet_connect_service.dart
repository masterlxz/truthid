import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:web3dart/crypto.dart' show bytesToHex;

/// Wrapper fino sobre `ReownAppKitModal` (pacote `reown_appkit`) — isola a
/// API do pacote do resto do app, mesmo princípio de `BlockchainService`
/// isolar o transporte JSON-RPC cru dos call sites. Parte da infra de P68
/// (fatia 1: WalletConnect + criar identidade 100% pelo Mobile).
///
/// Só a rede Base Mainnet é suportada — mesma única rede que o resto do app
/// já usa (`BlockchainService.chainId`).
class WalletConnectService {
  static const _projectId = 'ecf672e1e9d165bb65017b793e80c0af';

  // CAIP-2: "eip155:<chainId>" — formato que tanto `session.chainId` quanto
  // o parâmetro `chainId` de `ReownAppKitModal.request()` exigem.
  static const _chainIdCaip2 = 'eip155:8453';
  static const _namespace = 'eip155';

  ReownAppKitModal? _modal;

  Future<void> init(BuildContext context) async {
    _modal = ReownAppKitModal(
      context: context,
      projectId: _projectId,
      metadata: const PairingMetadata(
        name: 'TruthID',
        description: 'Identidade descentralizada auto-custodiada',
        url: 'https://masterlxz.github.io/truthid',
        icons: [
          'https://masterlxz.github.io/truthid/favicon.png',
        ],
        // Esquema dedicado (não o "truthid://" já usado por DeepLinkService)
        // pra evitar colisão: uma wallet devolvendo foco ao app depois de
        // assinar/enviar não pode ser confundida com um deep link de
        // pareamento/sessão. Ver AndroidManifest.xml/Info.plist.
        redirect: Redirect(native: 'truthidwc://', linkMode: false),
      ),
    );
    await _modal!.init();
  }

  bool get isConnected => _modal?.isConnected ?? false;

  String? get connectedAddress =>
      _modal?.session?.getAddress(_namespace);

  int? get connectedChainId {
    final chainId = _modal?.session?.chainId;
    if (chainId == null) return null;
    return int.tryParse(chainId.split(':').last);
  }

  /// Abre a modal de conexão (deep-link ou QR, conforme a wallet escolhida)
  /// e espera o resultado — resolve quando `onModalConnect` dispara, lança
  /// se `onModalError` disparar primeiro (ex: usuário rejeitou/fechou a modal).
  ///
  /// `timeout` cobre o caso do pacote não disparar nenhum dos dois eventos
  /// (ex: usuário fecha a modal no botão voltar/tap fora, sem confirmar
  /// nem cancelar) — sem isso, `connectWallet()` travaria com `_busy` preso
  /// pra sempre, sem jeito de tentar de novo sem sair da tela.
  Future<void> openConnectModal({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final modal = _modal;
    if (modal == null) {
      throw StateError('WalletConnectService.init() must be called first.');
    }

    final completer = Completer<void>();
    late void Function(ModalConnect) onConnect;
    late void Function(ModalError) onError;

    void cleanup() {
      modal.onModalConnect.unsubscribe(onConnect);
      modal.onModalError.unsubscribe(onError);
    }

    onConnect = (args) {
      if (!completer.isCompleted) completer.complete();
      cleanup();
    };
    onError = (args) {
      if (!completer.isCompleted) {
        completer.completeError(Exception(args.message));
      }
      cleanup();
    };

    modal.onModalConnect.subscribe(onConnect);
    modal.onModalError.subscribe(onError);

    await modal.openModalView();
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      cleanup();
      throw Exception(
          'WalletConnect: connection modal timed out after $timeout.');
    }
  }

  /// `personal_sign` (EIP-191) sobre os bytes crus de `message` — quem chama
  /// decide se é um hash de 32 bytes (consentimento de createIdentity) ou uma
  /// string arbitrária (ex: a mensagem fixa da vault key), ambos os casos já
  /// vêm como bytes prontos, sem prefixo aplicado aqui (a wallet conectada
  /// aplica o prefixo "\x19Ethereum Signed Message:\n{len}" sozinha, mesma
  /// convenção da Ledger/Trezor no Desktop).
  Future<String> personalSign(Uint8List message) async {
    final modal = _modal;
    final address = connectedAddress;
    if (modal == null || address == null) {
      throw StateError('WalletConnect: not connected.');
    }

    final messageHex = bytesToHex(message, include0x: true);
    final result = await modal.request(
      topic: modal.session!.topic,
      chainId: _chainIdCaip2,
      request: SessionRequestParams(
        method: 'personal_sign',
        params: [messageHex, address],
      ),
    );
    return result as String;
  }

  /// `eth_sendTransaction` — sem forçar `gas` (deixa a wallet conectada
  /// estimar sozinha; o `gas: 30_000n` que o Desktop usa é um workaround
  /// específico do Tauri/viem que não se aplica aqui). Retorna o hash da
  /// transação (não o recibo — quem chama faz polling, ver
  /// CreateIdentityScreen).
  Future<String> sendTransaction({
    required String to,
    BigInt? valueWei,
    String? data,
  }) async {
    final modal = _modal;
    final address = connectedAddress;
    if (modal == null || address == null) {
      throw StateError('WalletConnect: not connected.');
    }

    final tx = <String, dynamic>{
      'from': address,
      'to': to,
      if (valueWei != null && valueWei > BigInt.zero)
        'value': '0x${valueWei.toRadixString(16)}',
      if (data != null) 'data': data,
    };

    final result = await modal.request(
      topic: modal.session!.topic,
      chainId: _chainIdCaip2,
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [tx],
      ),
    );
    return result as String;
  }

  Future<void> dispose() async {
    await _modal?.dispose();
    _modal = null;
  }
}

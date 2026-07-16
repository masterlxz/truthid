import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Servidor HTTP efêmero (mesmo padrão de `VaultLanServerService`, mas em
/// módulo próprio — canal separado da Vault, mesma razão que o Desktop já
/// mantém `local_signer_server.rs` (app terceiro) fora de tudo que é Vault)
/// que o mobile sobe para entregar o resultado de um pedido de assinatura
/// (`/sign-message`/`/sign-request` cross-device) para um app terceiro na
/// mesma rede local.
///
/// Bloco de portas próprio, distinto de `47850..47854` (Vault LAN,
/// `VaultLanServerService`) e `47950..47954` (Desktop `local_signer_server.rs`,
/// canal loopback com app terceiro) — precisa ser espelhado manualmente do
/// lado do app terceiro quando essa integração existir.
class RemoteSignerLanServer {
  static const candidatePorts = [48050, 48051, 48052, 48053, 48054];

  HttpServer? _server;

  /// Sobe o servidor na primeira porta livre da lista, responde exatamente 1
  /// request GET em `/session/<sessionId>` com `{"blob": "<base64>"}` e
  /// fecha. Se ninguém bater na porta certa antes de `expiresAt`, fecha
  /// sozinho sem servir nada. Retorna `true` se serviu, `false` se expirou.
  Future<bool> serveOnce({
    required Uint8List encryptedBlob,
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    final server = await _bindFirstAvailable();
    _server = server;

    final completer = Completer<bool>();
    final expectedPath = '/session/$sessionId';
    final responseBody =
        utf8.encode(jsonEncode({'blob': base64Encode(encryptedBlob)}));

    final subscription = server.listen((request) async {
      // 404 uniforme pra path/sessionId errado — não vaza sinal de "quase
      // certo" pra quem estiver varrendo a rede sem o QR correto.
      if (request.method != 'GET' || request.uri.path != expectedPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.add(responseBody);
      await request.response.close();

      if (!completer.isCompleted) completer.complete(true);
    });

    final remaining = expiresAt.difference(DateTime.now());
    final timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
      await server.close(force: true);
      _server = null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<HttpServer> _bindFirstAvailable() async {
    Object? lastError;
    for (final port in candidatePorts) {
      try {
        return await HttpServer.bind(InternetAddress.anyIPv4, port);
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      'no available port among $candidatePorts to serve the sign-message result'
      '${lastError != null ? ': $lastError' : ''}',
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Servidor HTTP efêmero (dart:io puro, sem `shelf` — só 1 endpoint, sem
/// roteamento de verdade) que o mobile sobe para entregar um vault-session
/// já cifrado (ECIES) para a extensão de navegador via LAN (13.9, fatia 1).
///
/// Lista de portas espelhada em `extension/src/session/lanDiscovery.ts` — as
/// duas precisam ficar em sincronia manual, mesmo padrão já usado nos outros
/// pares Dart/Rust/TS deste projeto.
class VaultLanServerService {
  static const candidatePorts = [47850, 47851, 47852, 47853, 47854];

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
      'no available port among $candidatePorts to serve the vault session'
      '${lastError != null ? ': $lastError' : ''}',
    );
  }

  /// IPs locais (IPv4, não-loopback) do celular, para mostrar na tela de
  /// envio como fallback manual — a extensão pode não conseguir descobrir a
  /// rede sozinha (ex: Firefox, sem `chrome.system.network`).
  static Future<List<String>> getLocalIpAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return interfaces
        .expand((interface) => interface.addresses)
        .map((address) => address.address)
        .toList();
  }
}

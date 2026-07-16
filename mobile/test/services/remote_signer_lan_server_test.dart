import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';

// Teste puro (test(), não testWidgets) — bind de socket real e request HTTP
// real. Rodar isso dentro de um testWidgets travaria pra sempre (I/O real não
// resolve dentro da zona FakeAsync do binding de widget, achado real da
// Sessão 98 — VaultRepository nos testes de tela precisou virar mock por
// causa disso). Aqui não tem widget nenhum, só a lógica pura do servidor.
void main() {
  group('RemoteSignerLanServer.serveOnce', () {
    test('responde com o blob correto no path esperado', () async {
      final server = RemoteSignerLanServer();
      final blob = Uint8List.fromList([1, 2, 3, 4, 5]);
      final expiresAt = DateTime.now().add(const Duration(seconds: 5));

      final serveFuture = server.serveOnce(
        encryptedBlob: blob,
        sessionId: 'abc123',
        expiresAt: expiresAt,
      );

      final port = await _waitForOpenPort();
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/session/abc123'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, 200);
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        expect(base64Decode(decoded['blob'] as String), blob);
      } finally {
        client.close(force: true);
      }

      expect(await serveFuture, isTrue);
    });

    test('devolve 404 uniforme pra path/sessionId errado', () async {
      final server = RemoteSignerLanServer();
      final expiresAt = DateTime.now().add(const Duration(seconds: 5));

      final serveFuture = server.serveOnce(
        encryptedBlob: Uint8List.fromList([9]),
        sessionId: 'the-real-session',
        expiresAt: expiresAt,
      );

      final port = await _waitForOpenPort();
      final client = HttpClient();
      try {
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/session/wrong-id'));
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 404);
      } finally {
        client.close(force: true);
      }

      // A requisição errada não conta como "servido" — o servidor continua
      // esperando o request certo até expirar.
      expect(await serveFuture, isFalse);
    });

    test('expira e devolve false quando ninguém conecta', () async {
      final server = RemoteSignerLanServer();
      final served = await server.serveOnce(
        encryptedBlob: Uint8List.fromList([1]),
        sessionId: 'never-requested',
        expiresAt: DateTime.now().add(const Duration(milliseconds: 50)),
      );

      expect(served, isFalse);
    });
  });
}

// O bind acontece dentro de serveOnce (assíncrono); como o teste não tem
// acesso direto à porta escolhida, tenta conectar em cada porta candidata
// até achar a que está de pé — mesmas portas de RemoteSignerLanServer.
Future<int> _waitForOpenPort() async {
  for (var attempt = 0; attempt < 50; attempt++) {
    for (final port in RemoteSignerLanServer.candidatePorts) {
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 50));
        await socket.close();
        return port;
      } catch (_) {
        // ainda não subiu nessa porta — tenta a próxima
      }
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('no RemoteSignerLanServer port came up in time');
}

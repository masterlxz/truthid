import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_client.dart';
import 'package:truthid_mobile/services/arweave_jwk.dart';
import 'package:truthid_mobile/services/arweave_merkle.dart';
import 'package:truthid_mobile/services/arweave_transaction.dart';

// Teste puro (test(), não testWidgets) — bind de socket real e request HTTP
// real. I/O real não resolve dentro da zona FakeAsync do binding de widget
// (achado real da Sessão 98, ver remote_signer_lan_server_test.dart).
void main() {
  final testWalletJson = File('test/fixtures/arweave/test_wallet.json').readAsStringSync();

  group('arweave_client — endpoints individuais', () {
    test('getPrice lê o corpo texto do /price/{bytes}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? capturedPath;
      server.listen((request) async {
        capturedPath = request.uri.path;
        request.response.statusCode = 200;
        request.response.write('123456789');
        await request.response.close();
      });
      addTearDown(server.close);

      final price = await getPrice('http://127.0.0.1:${server.port}', 4096);
      expect(price, '123456789');
      expect(capturedPath, '/price/4096');
    });

    test('getTxAnchor lê o corpo texto do /tx_anchor', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/tx_anchor');
        request.response.statusCode = 200;
        request.response.write('anchor-value');
        await request.response.close();
      });
      addTearDown(server.close);

      expect(await getTxAnchor('http://127.0.0.1:${server.port}'), 'anchor-value');
    });

    test('getWalletBalance lê o corpo texto do /wallet/{address}/balance', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/wallet/abc123/balance');
        request.response.statusCode = 200;
        request.response.write('999');
        await request.response.close();
      });
      addTearDown(server.close);

      expect(await getWalletBalance('http://127.0.0.1:${server.port}', 'abc123'), '999');
    });

    test('fetchData lê os bytes crus do GET /{id}', () async {
      final expected = Uint8List.fromList([1, 2, 3, 4, 5, 255]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/tx-id-123');
        request.response.statusCode = 200;
        request.response.add(expected);
        await request.response.close();
      });
      addTearDown(server.close);

      final fetched = await fetchData('http://127.0.0.1:${server.port}', 'tx-id-123');
      expect(fetched, expected);
    });

    test('getTxStatus confirmado quando 200 com corpo JSON', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/tx/abc/status');
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'block_height': 42, 'number_of_confirmations': 7}));
        await request.response.close();
      });
      addTearDown(server.close);

      final status = await getTxStatus('http://127.0.0.1:${server.port}', 'abc');
      expect(status.confirmed, isTrue);
      expect(status.blockHeight, 42);
      expect(status.numberOfConfirmations, 7);
    });

    test('getTxStatus não-confirmado quando status != 200 (sem lançar)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });
      addTearDown(server.close);

      final status = await getTxStatus('http://127.0.0.1:${server.port}', 'abc');
      expect(status.confirmed, isFalse);
      expect(status.blockHeight, isNull);
    });

    test('submitTransaction manda o corpo de toWireJson via POST /tx', () async {
      Map<String, dynamic>? capturedBody;
      String? capturedMethod;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        capturedMethod = request.method;
        final text = await utf8.decoder.bind(request).join();
        capturedBody = jsonDecode(text) as Map<String, dynamic>;
        request.response.statusCode = 200;
        await request.response.close();
      });
      addTearDown(server.close);

      final jwk = parseJwk(testWalletJson);
      final tx = buildTransaction(
        Uint8List.fromList(utf8.encode('hi')),
        [('A', 'B')],
        '1000',
        'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo',
        jwk.n,
      );

      await submitTransaction('http://127.0.0.1:${server.port}', tx);
      expect(capturedMethod, 'POST');
      expect(capturedBody!['data'], isNot(''));
      expect(capturedBody!['format'], 2);
    });

    test('submitTransactionNoData manda data vazio', () async {
      Map<String, dynamic>? capturedBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        capturedBody = jsonDecode(text) as Map<String, dynamic>;
        request.response.statusCode = 200;
        await request.response.close();
      });
      addTearDown(server.close);

      final jwk = parseJwk(testWalletJson);
      final tx = buildTransaction(
        Uint8List.fromList(utf8.encode('hi')),
        [],
        '1000',
        'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo',
        jwk.n,
      );

      await submitTransactionNoData('http://127.0.0.1:${server.port}', tx);
      expect(capturedBody!['data'], '');
    });

    test('submitChunk manda offset/data_size como string e aceita resposta texto puro OK', () async {
      Map<String, dynamic>? capturedBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/chunk');
        final text = await utf8.decoder.bind(request).join();
        capturedBody = jsonDecode(text) as Map<String, dynamic>;
        request.response.statusCode = 200;
        request.response.write('OK'); // texto puro, não JSON — não deve quebrar o parse
        await request.response.close();
      });
      addTearDown(server.close);

      final proof = Proof(12345, Uint8List.fromList([9, 9, 9]));
      await submitChunk(
        'http://127.0.0.1:${server.port}',
        'data-root-b64',
        '999',
        proof,
        Uint8List.fromList([1, 2, 3]),
      );

      expect(capturedBody!['offset'], '12345'); // string, não número
      expect(capturedBody!['data_size'], '999'); // string, não número
      expect(capturedBody!['data_root'], 'data-root-b64');
    });

    test('submitChunk lança com status+corpo quando o node rejeita', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 400;
        request.response.write('prova inválida');
        await request.response.close();
      });
      addTearDown(server.close);

      final proof = Proof(0, Uint8List.fromList([1]));
      await expectLater(
        submitChunk('http://127.0.0.1:${server.port}', 'root', '10', proof, Uint8List.fromList([1])),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('400'), contains('prova inválida')),
        )),
      );
    });
  });

  group('arweave_client — publish() ponta a ponta contra servidor local', () {
    test('conteúdo pequeno publica inline (1 POST /tx, nenhum /chunk)', () async {
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        paths.add('${request.method} ${request.uri.path}');
        await request.drain<void>();
        request.response.statusCode = 200;
        if (request.uri.path.startsWith('/price/')) {
          request.response.write('100000');
        } else if (request.uri.path == '/tx_anchor') {
          request.response.write('qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo');
        }
        await request.response.close();
      });
      addTearDown(server.close);

      final jwk = parseJwk(testWalletJson);
      final txId = await publish(
        'http://127.0.0.1:${server.port}',
        jwk,
        Uint8List.fromList(utf8.encode('conteúdo pequeno, 1 chunk só')),
        [],
      );

      expect(txId.isNotEmpty, isTrue);
      expect(paths.where((p) => p.contains('/chunk')), isEmpty);
      expect(paths.where((p) => p == 'POST /tx').length, 1);
    });

    test('conteúdo multi-chunk publica em chunks sequenciais, nunca concorrentes', () async {
      var active = 0;
      var maxActive = 0;
      final chunkOrder = <int>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/chunk') {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          final text = await utf8.decoder.bind(request).join();
          final body = jsonDecode(text) as Map<String, dynamic>;
          chunkOrder.add(int.parse(body['offset'] as String));
          // atraso artificial — se o cliente disparasse chunks em paralelo,
          // duas requisições estariam "active" ao mesmo tempo aqui dentro.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          request.response.statusCode = 200;
          request.response.write('OK');
          await request.response.close();
          return;
        }
        await request.drain<void>();
        request.response.statusCode = 200;
        if (path.startsWith('/price/')) {
          request.response.write('100000000');
        } else if (path == '/tx_anchor') {
          request.response.write('qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo');
        }
        await request.response.close();
      });
      addTearDown(server.close);

      final jwk = parseJwk(testWalletJson);
      final content = Uint8List(maxChunkSize * 2 + 500)..fillRange(0, maxChunkSize * 2 + 500, 0xAB);
      final txId = await publish('http://127.0.0.1:${server.port}', jwk, content, []);

      expect(txId.isNotEmpty, isTrue);
      expect(chunkOrder.length, 3, reason: 'mesmo conteúdo de teste do merkle — 3 chunks reais');
      expect(maxActive, 1, reason: 'upload de chunk nunca deve ser concorrente');
      // ordem crescente de offset — mesma ordem de chunkDataForUpload
      expect(chunkOrder, [chunkOrder[0], chunkOrder[1], chunkOrder[2]]..sort());
    });
  });
}

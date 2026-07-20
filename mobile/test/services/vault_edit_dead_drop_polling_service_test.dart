import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/vault_edit_dead_drop_polling_service.dart';

void main() {
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';

  group('VaultEditDeadDropPollingService.tryFetch', () {
    test('devolve os bytes quando o gateway responde 200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.add(bytes);
        await request.response.close();
      });

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://${server.address.address}:${server.port}',
      );

      final result = await service.tryFetch(sessionIdHex);
      expect(result, equals(bytes));

      await server.close(force: true);
    });

    test('devolve null (não lança) quando o gateway responde não-200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://${server.address.address}:${server.port}',
      );

      expect(await service.tryFetch(sessionIdHex), isNull);

      await server.close(force: true);
    });

    test('devolve null (não lança) em erro de rede', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://127.0.0.1:$port',
        requestTimeout: const Duration(milliseconds: 300),
      );

      expect(await service.tryFetch(sessionIdHex), isNull);
    });

    test('acha o nome IPNS certo na URL (mesmo namespace de dead-drop do vault-edit)', () async {
      String? requestedPath;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requestedPath = request.uri.path;
        request.response.statusCode = 200;
        request.response.add(Uint8List.fromList([1]));
        await request.response.close();
      });

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://${server.address.address}:${server.port}',
      );
      await service.tryFetch(sessionIdHex);

      expect(
        requestedPath,
        '/ipns/k51qzi5uqu5djgtmynxex3q39osopskdt54vg2txhdkfjcwo1114qqv9n9uld9',
      );

      await server.close(force: true);
    });
  });

  group('VaultEditDeadDropPollingService.pollUntil', () {
    test('retenta até o conteúdo aparecer', () async {
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = Uint8List.fromList([7, 7, 7]);
      server.listen((request) async {
        requestCount++;
        if (requestCount < 3) {
          request.response.statusCode = 500;
        } else {
          request.response.statusCode = 200;
          request.response.add(bytes);
        }
        await request.response.close();
      });

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://${server.address.address}:${server.port}',
        pollInterval: const Duration(milliseconds: 20),
      );

      final result = await service.pollUntil(
        sessionIdHex,
        DateTime.now().add(const Duration(seconds: 5)),
      );

      expect(result, equals(bytes));
      expect(requestCount, greaterThanOrEqualTo(3));

      await server.close(force: true);
    });

    test('devolve null se expirar sem achar conteúdo', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });

      final service = VaultEditDeadDropPollingService(
        gatewayUrl: 'http://${server.address.address}:${server.port}',
        pollInterval: const Duration(milliseconds: 20),
      );

      final result = await service.pollUntil(
        sessionIdHex,
        DateTime.now().add(const Duration(milliseconds: 100)),
      );

      expect(result, isNull);

      await server.close(force: true);
    });
  });
}

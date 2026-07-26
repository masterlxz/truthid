import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/lan_sweep_client.dart';

void main() {
  group('subnetHosts', () {
    test('generates all 254 hosts of the /24', () {
      final hosts = subnetHosts('192.168.1.42');
      expect(hosts, hasLength(254));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
    });

    test('returns empty for a malformed address', () {
      expect(subnetHosts('not-an-ip'), isEmpty);
    });
  });

  group('localIpAddresses', () {
    test('returns at least one address on a machine with networking', () async {
      final ips = await localIpAddresses();
      // Environment-dependent (CI/sandboxes may have zero non-loopback
      // interfaces) — just prove it doesn't throw and returns a list.
      expect(ips, isA<List<String>>());
    });
  });

  group('fetchSessionBlob / putSessionContent against a real local server', () {
    late HttpServer server;
    late String host;
    late int port;

    tearDown(() async {
      await server.close(force: true);
    });

    test('fetchSessionBlob decodes the base64 blob from a 200 response', () async {
      final expectedBlob = Uint8List.fromList([1, 2, 3, 4, 5]);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = server.address.address;
      port = server.port;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'blob': base64Encode(expectedBlob)}));
        await request.response.close();
      });

      final client = HttpClient();
      final result = await fetchSessionBlob(client, host, port, 'session-1');
      client.close();

      expect(result, expectedBlob);
    });

    test('fetchSessionBlob returns null on a non-200 response', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = server.address.address;
      port = server.port;
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });

      final client = HttpClient();
      final result = await fetchSessionBlob(client, host, port, 'session-1');
      client.close();

      expect(result, isNull);
    });

    test('fetchSessionBlob returns null when nothing is listening', () async {
      final client = HttpClient();
      final result = await fetchSessionBlob(
        client,
        '127.0.0.1',
        1, // reserved, nothing listens here
        'session-1',
        timeout: const Duration(milliseconds: 200),
      );
      client.close();

      expect(result, isNull);
    });

    test('putSessionContent succeeds against a 200 response and delivers the body', () async {
      final sentBody = Uint8List.fromList([9, 8, 7]);
      final received = <int>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = server.address.address;
      port = server.port;
      server.listen((request) async {
        await for (final chunk in request) {
          received.addAll(chunk);
        }
        request.response.statusCode = 200;
        await request.response.close();
      });

      final client = HttpClient();
      final ok = await putSessionContent(client, host, port, 'session-1', sentBody);
      client.close();

      expect(ok, isTrue);
      expect(received, sentBody);
    });

    test('putSessionContent returns false on a non-200 response', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = server.address.address;
      port = server.port;
      server.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });

      final client = HttpClient();
      final ok = await putSessionContent(
        client,
        host,
        port,
        'session-1',
        Uint8List.fromList([1]),
      );
      client.close();

      expect(ok, isFalse);
    });
  });
}

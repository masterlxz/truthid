import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/dead_drop_poll_client.dart';

void main() {
  const sessionId = '000102030405060708090a0b0c0d0e0f';

  late HttpServer server;

  tearDown(() async {
    await server.close(force: true);
  });

  test('tryFetch returns the body bytes on a 200 response', () async {
    final expectedBytes = Uint8List.fromList([10, 20, 30]);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(expectedBytes);
      await request.response.close();
    });

    final client = DeadDropPollClient(
      gatewayUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await client.tryFetch(sessionId);

    expect(result, expectedBytes);
  });

  test('tryFetch treats a non-200 response as "not yet" (never throws)', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 500; // Kubo's "not propagated yet" status
      await request.response.close();
    });

    final client = DeadDropPollClient(
      gatewayUrl: 'http://${server.address.address}:${server.port}',
    );
    final result = await client.tryFetch(sessionId);

    expect(result, isNull);
  });

  test('pollUntil returns null once expiresAt has passed with nothing found', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 500;
      await request.response.close();
    });

    final client = DeadDropPollClient(
      gatewayUrl: 'http://${server.address.address}:${server.port}',
      pollInterval: const Duration(milliseconds: 50),
    );
    final result = await client.pollUntil(
      sessionId,
      DateTime.now().add(const Duration(milliseconds: 120)),
    );

    expect(result, isNull);
  });

  test('pollUntil returns content as soon as it becomes available', () async {
    final expectedBytes = Uint8List.fromList([1, 2, 3]);
    var attempt = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      attempt++;
      if (attempt < 2) {
        request.response.statusCode = 500;
      } else {
        request.response.add(expectedBytes);
      }
      await request.response.close();
    });

    final client = DeadDropPollClient(
      gatewayUrl: 'http://${server.address.address}:${server.port}',
      pollInterval: const Duration(milliseconds: 50),
    );
    final result = await client.pollUntil(
      sessionId,
      DateTime.now().add(const Duration(seconds: 5)),
    );

    expect(result, expectedBytes);
    expect(attempt, greaterThanOrEqualTo(2));
  });
}

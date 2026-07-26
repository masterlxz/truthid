import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/dead_drop_poll_client.dart';
import 'package:truthid_sdk/src/internal/ecies.dart';
import 'package:truthid_sdk/src/requester.dart';

// Real network sweeps/dead-drop are exercised at the lower level in
// test/internal/lan_sweep_client_test.dart and dead_drop_poll_client_test.dart
// (which talk to real local HTTP servers over loopback). Here, the LAN
// sweep and dead-drop are injected fakes — this suite is about
// TruthIDRequester's own orchestration (payload shape, racing LAN vs
// dead-drop, decrypting the winner, retry-until-timeout), not about real
// sockets. A genuine end-to-end run needs a second physical device on the
// same network — self-connecting a container to its own external IP hits a
// Docker hairpin-NAT limitation that has nothing to do with this code.
DeadDropPollClient _deadFastDeadDrop() => DeadDropPollClient(
      gatewayUrl: 'http://127.0.0.1:9', // discard port, connection refused fast
      pollInterval: const Duration(milliseconds: 50),
      requestTimeout: const Duration(milliseconds: 100),
    );

void main() {
  test('delivers a signed result via the injected LAN sweep', () async {
    final ecies = EciesService();
    Uint8List? blobToServe;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepForResult: (sessionId) async => blobToServe,
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.signMessage(
      appName: 'Test App',
      purpose: 'login',
      timeout: const Duration(seconds: 5),
    );

    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    expect(payload['action'], 'truthid-sign-message');
    expect(payload['v'], 1);
    expect(payload['sessionId'], pending.sessionId);
    expect(payload['appName'], 'Test App');
    expect(payload['purpose'], 'login');
    final ephemeralPubKey = payload['ephemeralPubKey'] as String;

    final resultJson = {
      'status': 'signed',
      'message': 'TruthID Message Signing: Test App:login',
      'signature': '0xdeadbeef',
    };
    blobToServe = await ecies.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(resultJson))),
      ephemeralPubKey,
    );

    final result = await pending.result;

    expect(result.delivered, isTrue);
    expect(result.data!.status, 'signed');
    expect(result.data!.message, 'TruthID Message Signing: Test App:login');
    expect(result.data!.signature, '0xdeadbeef');
  });

  test('reports not delivered when nothing answers before expiresAt', () async {
    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepForResult: (sessionId) async => null,
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.signMessage(
      appName: 'Test App',
      purpose: 'login',
      timeout: const Duration(seconds: 1),
    );

    final result = await pending.result;

    expect(result.delivered, isFalse);
    expect(result.data, isNull);
  });
}

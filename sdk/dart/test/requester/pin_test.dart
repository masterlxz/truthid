import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show AesGcm, SecretBox, SecretKey, Mac;
import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/dead_drop_poll_client.dart';
import 'package:truthid_sdk/src/internal/ecies.dart';
import 'package:truthid_sdk/src/internal/pin_content_cipher.dart';
import 'package:truthid_sdk/src/requester.dart';

DeadDropPollClient _deadFastDeadDrop() => DeadDropPollClient(
      gatewayUrl: 'http://127.0.0.1:9',
      pollInterval: const Duration(milliseconds: 50),
      requestTimeout: const Duration(milliseconds: 100),
    );

Future<Uint8List> _decryptPinContent(Uint8List blob, Uint8List key) async {
  final nonce = blob.sublist(0, 12);
  final rest = blob.sublist(12);
  final mac = rest.sublist(rest.length - 16);
  final ciphertext = rest.sublist(0, rest.length - 16);
  final plaintext = await AesGcm.with256bits().decrypt(
    SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return Uint8List.fromList(plaintext);
}

void main() {
  test('pushes the encrypted content, then delivers the pinned result', () async {
    final ecies = EciesService();
    final content = Uint8List.fromList('file contents to pin'.codeUnits);
    Uint8List? pushedBody;
    Uint8List? resultBlobToServe;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async {
        pushedBody = body;
        return true;
      },
      lanSweepForResult: (sessionId) async => resultBlobToServe,
    );

    final pending = requester.pin(
      appName: 'Test App',
      content: content,
      timeout: const Duration(seconds: 5),
    );

    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    expect(payload['action'], 'truthid-pin');
    expect(payload['v'], 1);
    expect(payload['sessionId'], pending.sessionId);
    // Unlike sign-message/sign-request, /pin's QR carries no content fields —
    // the content is pushed separately over LAN, not embedded in the QR.
    expect(payload.containsKey('content'), isFalse);
    final ephemeralPubKey = payload['ephemeralPubKey'] as String;

    // Wait for the phase-1 push to actually happen before preparing the
    // phase-2 response — mirrors the real sequencing (phone must receive
    // and decrypt the content before it can ever produce a pin result).
    while (pushedBody == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Prove the pushed blob is genuinely decryptable with the sessionId-
    // derived key, exactly like the mobile's phase-1 receiver would.
    final contentKey = derivePinContentKey(pending.sessionId);
    final decryptedPush = await _decryptPinContent(pushedBody!, contentKey);
    expect(decryptedPush, content);

    final resultJson = {
      'status': 'pinned',
      'cid': 'ar://abc123',
      'contentHash': '0xhash',
      'providersOk': ['arweave'],
      'providersFailed': <String>[],
    };
    resultBlobToServe = await ecies.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(resultJson))),
      ephemeralPubKey,
    );

    final result = await pending.result;

    expect(result.delivered, isTrue);
    expect(result.data!.status, 'pinned');
    expect(result.data!.cid, 'ar://abc123');
    expect(result.data!.contentHash, '0xhash');
    expect(result.data!.providersOk, ['arweave']);
    expect(result.data!.providersFailed, isEmpty);
  });

  test('never attempts phase 2 if phase 1 (the push) never succeeds', () async {
    var phase2Attempts = 0;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => false,
      lanSweepForResult: (sessionId) async {
        phase2Attempts++;
        return null;
      },
    );

    final pending = requester.pin(
      appName: 'Test App',
      content: Uint8List.fromList([1, 2, 3]),
      timeout: const Duration(milliseconds: 500),
    );

    final result = await pending.result;

    expect(result.delivered, isFalse);
    expect(phase2Attempts, 0);
  });

  test('reports rejected/failed statuses from the phone', () async {
    final ecies = EciesService();
    Uint8List? resultBlobToServe;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => true,
      lanSweepForResult: (sessionId) async => resultBlobToServe,
    );

    final pending = requester.pin(
      appName: 'Test App',
      content: Uint8List.fromList([1, 2, 3]),
      timeout: const Duration(seconds: 5),
    );
    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    final ephemeralPubKey = payload['ephemeralPubKey'] as String;

    resultBlobToServe = await ecies.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode({'status': 'rejected'}))),
      ephemeralPubKey,
    );

    final result = await pending.result;
    expect(result.delivered, isTrue);
    expect(result.data!.status, 'rejected');
  });
}

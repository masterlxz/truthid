import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/dead_drop_poll_client.dart';
import 'package:truthid_sdk/src/internal/ecies.dart';
import 'package:truthid_sdk/src/requester.dart';

DeadDropPollClient _deadFastDeadDrop() => DeadDropPollClient(
      gatewayUrl: 'http://127.0.0.1:9',
      pollInterval: const Duration(milliseconds: 50),
      requestTimeout: const Duration(milliseconds: 100),
    );

void main() {
  test('builds the exact payload schema and delivers an executed result', () async {
    final ecies = EciesService();
    Uint8List? blobToServe;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepForResult: (sessionId) async => blobToServe,
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.signRequest(
      appName: 'Test App',
      dest: '0xcccccccccccccccccccccccccccccccccccccccc',
      callData: '0xa9059cbb',
      functionSignature: 'transfer(address,uint256)',
      value: '1000',
      timeout: const Duration(seconds: 5),
    );

    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    expect(payload['action'], 'truthid-sign-request');
    expect(payload['v'], 1);
    expect(payload['dest'], '0xcccccccccccccccccccccccccccccccccccccccc');
    expect(payload['callData'], '0xa9059cbb');
    expect(payload['functionSignature'], 'transfer(address,uint256)');
    expect(payload['value'], '1000');
    final ephemeralPubKey = payload['ephemeralPubKey'] as String;

    final resultJson = {
      'status': 'executed',
      'userOpHash': '0xUserOpHashXYZ',
      'transactionHash': '0xTxHash',
    };
    blobToServe = await ecies.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(resultJson))),
      ephemeralPubKey,
    );

    final result = await pending.result;

    expect(result.delivered, isTrue);
    expect(result.data!.status, 'executed');
    expect(result.data!.userOpHash, '0xUserOpHashXYZ');
    expect(result.data!.transactionHash, '0xTxHash');
  });

  test('defaults value to "0" when omitted', () async {
    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepForResult: (sessionId) async => null,
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.signRequest(
      appName: 'Test App',
      dest: '0xcccccccccccccccccccccccccccccccccccccccc',
      callData: '0xa9059cbb',
      functionSignature: 'transfer(address,uint256)',
      timeout: const Duration(milliseconds: 500),
    );

    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    expect(payload['value'], '0');

    await pending.result; // let it time out cleanly before the test ends
  });

  test('surfaces a failed execution', () async {
    final ecies = EciesService();
    Uint8List? blobToServe;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepForResult: (sessionId) async => blobToServe,
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.signRequest(
      appName: 'Test App',
      dest: '0xcccccccccccccccccccccccccccccccccccccccc',
      callData: '0xa9059cbb',
      functionSignature: 'transfer(address,uint256)',
      timeout: const Duration(seconds: 5),
    );
    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    final ephemeralPubKey = payload['ephemeralPubKey'] as String;

    final resultJson = {
      'status': 'failed',
      'error': 'insufficient funds for gas',
    };
    blobToServe = await ecies.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(resultJson))),
      ephemeralPubKey,
    );

    final result = await pending.result;

    expect(result.delivered, isTrue);
    expect(result.data!.status, 'failed');
    expect(result.data!.error, 'insufficient funds for gas');
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/dead_drop_poll_client.dart';
import 'package:truthid_sdk/src/internal/vault_edit_content_cipher.dart';
import 'package:truthid_sdk/src/requester.dart';

DeadDropPollClient _deadFastDeadDrop() => DeadDropPollClient(
      gatewayUrl: 'http://127.0.0.1:9',
      pollInterval: const Duration(milliseconds: 50),
      requestTimeout: const Duration(milliseconds: 100),
    );

Future<Map<String, dynamic>> _decryptProposal(Uint8List blob, Uint8List key) async {
  final nonce = blob.sublist(0, 12);
  final rest = blob.sublist(12);
  final mac = rest.sublist(rest.length - 16);
  final ciphertext = rest.sublist(0, rest.length - 16);
  final plaintext = await AesGcm.with256bits().decrypt(
    SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
}

void main() {
  test('pushes the encrypted proposal over LAN, delivered resolves true', () async {
    Uint8List? pushedBody;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async {
        pushedBody = body;
        return true;
      },
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      url: 'https://example.com',
      username: 'alice',
      password: 'hunter2',
      timeout: const Duration(seconds: 5),
    );

    final payload = jsonDecode(pending.qrPayload) as Map<String, dynamic>;
    expect(payload['action'], 'truthid-vault-edit');
    expect(payload['v'], 1);
    expect(payload['sessionId'], pending.sessionId);
    expect(payload.containsKey('site'), isFalse); // proposal goes over LAN, not in the QR

    final delivered = await pending.delivered;
    expect(delivered, isTrue);

    final contentKey = deriveVaultEditContentKey(pending.sessionId);
    final proposal = await _decryptProposal(pushedBody!, contentKey);
    expect(proposal['site'], 'example.com');
    expect(proposal['url'], 'https://example.com');
    expect(proposal['username'], 'alice');
    expect(proposal['password'], 'hunter2');
    expect(proposal['notes'], '');
    expect(proposal.containsKey('passkey'), isFalse);
  });

  test('delivered resolves false if the LAN push never succeeds before timeout', () async {
    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => false,
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      username: 'alice',
      password: 'hunter2',
      timeout: const Duration(milliseconds: 500),
    );

    expect(await pending.delivered, isFalse);
  });

  test('publishes to the Kubo endpoint in parallel when pinningEndpointUrl is given', () async {
    String? publishedSessionId;
    Uint8List? publishedContent;
    String? publishedEndpoint;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => true,
      kuboPublish: (sessionId, content, endpointUrl) async {
        publishedSessionId = sessionId;
        publishedContent = content;
        publishedEndpoint = endpointUrl;
      },
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      username: 'alice',
      password: 'hunter2',
      pinningEndpointUrl: 'http://127.0.0.1:5001',
      timeout: const Duration(seconds: 5),
    );

    await pending.delivered;
    // O publish é fire-and-forget, disparado antes do push de LAN — dá
    // tempo dele completar já que os dois correm no mesmo microtask loop
    // sem I/O real na fake injetada.
    await Future<void>.delayed(Duration.zero);

    expect(publishedSessionId, pending.sessionId);
    expect(publishedEndpoint, 'http://127.0.0.1:5001');
    final contentKey = deriveVaultEditContentKey(pending.sessionId);
    final proposal = await _decryptProposal(publishedContent!, contentKey);
    expect(proposal['username'], 'alice');
  });

  test('does not attempt Kubo publish when pinningEndpointUrl is omitted', () async {
    var kuboPublishCalls = 0;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => true,
      kuboPublish: (sessionId, content, endpointUrl) async => kuboPublishCalls++,
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      username: 'alice',
      password: 'hunter2',
      timeout: const Duration(seconds: 5),
    );

    await pending.delivered;
    expect(kuboPublishCalls, 0);
  });

  test('a Kubo publish failure never affects delivered (best-effort)', () async {
    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async => true,
      kuboPublish: (sessionId, content, endpointUrl) async => throw StateError('kubo unreachable'),
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      username: 'alice',
      password: 'hunter2',
      pinningEndpointUrl: 'http://127.0.0.1:5001',
      timeout: const Duration(seconds: 5),
    );

    expect(await pending.delivered, isTrue);
  });

  test('accepts a passkey-only proposal (no password)', () async {
    Uint8List? pushedBody;

    final requester = TruthIDRequester(
      deadDropClient: _deadFastDeadDrop(),
      lanSweepToPush: (sessionId, body) async {
        pushedBody = body;
        return true;
      },
    );

    final pending = requester.vaultEdit(
      appName: 'Test App',
      site: 'example.com',
      username: 'alice',
      passkey: VaultEditPasskey(
        rpId: 'example.com',
        credentialIdB64: 'Y3JlZA',
        userHandleB64: 'dXNlcg',
        privateKeyHex: '0x${'ab' * 32}',
        signCount: 0,
        createdAt: 1700000000000,
      ),
      timeout: const Duration(seconds: 5),
    );

    await pending.delivered;

    final contentKey = deriveVaultEditContentKey(pending.sessionId);
    final proposal = await _decryptProposal(pushedBody!, contentKey);
    expect(proposal['password'], '');
    final passkey = proposal['passkey'] as Map<String, dynamic>;
    expect(passkey['rp_id'], 'example.com');
    expect(passkey['credential_id_b64'], 'Y3JlZA');
  });

  test('throws ArgumentError when neither password nor passkey is given', () {
    final requester = TruthIDRequester(deadDropClient: _deadFastDeadDrop());

    expect(
      () => requester.vaultEdit(appName: 'Test App', site: 'example.com', username: 'alice'),
      throwsArgumentError,
    );
  });
}

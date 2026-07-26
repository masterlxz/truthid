import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'internal/dead_drop_poll_client.dart';
import 'internal/ecies.dart';
import 'internal/lan_sweep_client.dart';
import 'internal/pin_content_cipher.dart';

const _defaultTimeout = Duration(minutes: 3);
const _lanRetryInterval = Duration(seconds: 2);

/// Sweeps the LAN for a phone answering `GET /session/<sessionId>` with a
/// result blob — see [sweepLanForResult] for the real implementation.
/// Injectable so callers (and this package's own tests) can substitute a
/// different strategy without touching real sockets.
typedef LanSweepForResult = Future<Uint8List?> Function(String sessionId);

/// Sweeps the LAN pushing [body] via `PUT` to a phone — see
/// [sweepLanToPush] for the real implementation.
typedef LanSweepToPush = Future<bool> Function(String sessionId, Uint8List body);

/// Outcome of a cross-device request: either the phone answered before
/// [PendingRequest.expiresAt], or it didn't.
class TransportResult<T> {
  final bool delivered;
  final T? data;

  const TransportResult({required this.delivered, this.data});
}

/// A cross-device request already in flight — the QR payload is ready to
/// display immediately; [result] resolves once the phone answers (over LAN
/// or dead-drop, whichever arrives first) or [expiresAt] passes.
class PendingRequest<T> {
  final String qrPayload;
  final String sessionId;
  final DateTime expiresAt;
  final Future<TransportResult<T>> result;

  const PendingRequest({
    required this.qrPayload,
    required this.sessionId,
    required this.expiresAt,
    required this.result,
  });
}

class SignMessageResult {
  final String status; // 'signed' | 'rejected'
  final String? message;
  final String? signature;

  const SignMessageResult({required this.status, this.message, this.signature});
}

class SignRequestResult {
  final String status; // 'executed' | 'failed' | 'rejected'
  final String? userOpHash;
  final String? transactionHash;
  final String? error;

  const SignRequestResult({
    required this.status,
    this.userOpHash,
    this.transactionHash,
    this.error,
  });
}

class PinResult {
  final String status; // 'pinned' | 'failed' | 'rejected'
  final String? cid;
  final String? contentHash;
  final List<String>? providersOk;
  final List<String>? providersFailed;
  final String? error;

  const PinResult({
    required this.status,
    this.cid,
    this.contentHash,
    this.providersOk,
    this.providersFailed,
    this.error,
  });
}

/// The requester role — the opposite side of what the mobile app's 5
/// cross-device approval screens do: build the QR payload for a
/// `sign-message`/`sign-request`/`pin` request, sweep the LAN and/or poll a
/// public IPFS gateway for the phone's encrypted response, decrypt it. No
/// TruthID-operated server involved — same transport the mobile app itself
/// uses (`RemoteSignerLanServer` + IPFS/IPNS dead-drop).
///
/// Deep-link transport (same-device, no QR) is out of scope: it would
/// require the host app to register its own URI scheme, which is
/// platform-specific and outside what a pure-Dart package can automate.
/// `vault-edit` (Vault credential proposals) is also out of scope for now —
/// see the SDK docs.
class TruthIDRequester {
  TruthIDRequester({
    DeadDropPollClient? deadDropClient,
    LanSweepForResult? lanSweepForResult,
    LanSweepToPush? lanSweepToPush,
  })  : _deadDropClient = deadDropClient ?? DeadDropPollClient(),
        _lanSweepForResult = lanSweepForResult ?? sweepLanForResult,
        _lanSweepToPush = lanSweepToPush ?? sweepLanToPush;

  final EciesService _ecies = EciesService();
  final DeadDropPollClient _deadDropClient;
  final LanSweepForResult _lanSweepForResult;
  final LanSweepToPush _lanSweepToPush;
  final _rng = Random.secure();

  PendingRequest<SignMessageResult> signMessage({
    required String appName,
    required String purpose,
    Duration timeout = _defaultTimeout,
  }) {
    final session = _newSession(timeout);
    final payload = {
      'action': 'truthid-sign-message',
      'v': 1,
      'sessionId': session.sessionId,
      'ephemeralPubKey': session.publicKeyHex,
      'expiresAt': session.expiresAtMs,
      'appName': appName,
      'purpose': purpose,
    };

    return PendingRequest(
      qrPayload: jsonEncode(payload),
      sessionId: session.sessionId,
      expiresAt: session.expiresAt,
      result: _awaitResult(session).then((json) {
        if (json == null) return const TransportResult(delivered: false);
        return TransportResult(
          delivered: true,
          data: SignMessageResult(
            status: json['status'] as String,
            message: json['message'] as String?,
            signature: json['signature'] as String?,
          ),
        );
      }),
    );
  }

  PendingRequest<SignRequestResult> signRequest({
    required String appName,
    required String dest,
    required String callData,
    required String functionSignature,
    String value = '0',
    Duration timeout = _defaultTimeout,
  }) {
    final session = _newSession(timeout);
    final payload = {
      'action': 'truthid-sign-request',
      'v': 1,
      'sessionId': session.sessionId,
      'ephemeralPubKey': session.publicKeyHex,
      'expiresAt': session.expiresAtMs,
      'appName': appName,
      'dest': dest,
      'callData': callData,
      'functionSignature': functionSignature,
      'value': value,
    };

    return PendingRequest(
      qrPayload: jsonEncode(payload),
      sessionId: session.sessionId,
      expiresAt: session.expiresAt,
      result: _awaitResult(session).then((json) {
        if (json == null) return const TransportResult(delivered: false);
        return TransportResult(
          delivered: true,
          data: SignRequestResult(
            status: json['status'] as String,
            userOpHash: json['userOpHash'] as String?,
            transactionHash: json['transactionHash'] as String?,
            error: json['error'] as String?,
          ),
        );
      }),
    );
  }

  PendingRequest<PinResult> pin({
    required String appName,
    required Uint8List content,
    Duration timeout = _defaultTimeout,
  }) {
    final session = _newSession(timeout);
    final payload = {
      'action': 'truthid-pin',
      'v': 1,
      'sessionId': session.sessionId,
      'ephemeralPubKey': session.publicKeyHex,
      'expiresAt': session.expiresAtMs,
      'appName': appName,
    };

    final resultFuture = () async {
      // Phase 1: push the encrypted content — the phone only starts
      // listening after it scans the QR, which can happen any time before
      // expiresAt, so this has to keep retrying rather than sweep once.
      final contentKey = derivePinContentKey(session.sessionId);
      final encryptedContent = await encryptPinContent(content, contentKey);
      final pushed = await _repeatUntilTrue(
        () => _lanSweepToPush(session.sessionId, encryptedContent),
        session.expiresAt,
        _lanRetryInterval,
      );
      if (!pushed) return const TransportResult<PinResult>(delivered: false);

      // Phase 2: same result race as the other two flows.
      final json = await _awaitResult(session);
      if (json == null) return const TransportResult<PinResult>(delivered: false);
      return TransportResult(
        delivered: true,
        data: PinResult(
          status: json['status'] as String,
          cid: json['cid'] as String?,
          contentHash: json['contentHash'] as String?,
          providersOk: (json['providersOk'] as List?)?.cast<String>(),
          providersFailed: (json['providersFailed'] as List?)?.cast<String>(),
          error: json['error'] as String?,
        ),
      );
    }();

    return PendingRequest(
      qrPayload: jsonEncode(payload),
      sessionId: session.sessionId,
      expiresAt: session.expiresAt,
      result: resultFuture,
    );
  }

  _Session _newSession(Duration timeout) {
    final sessionIdBytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      sessionIdBytes[i] = _rng.nextInt(256);
    }
    final sessionId =
        sessionIdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final keyPair = _ecies.generateKeyPair();
    final expiresAt = DateTime.now().add(timeout);

    return _Session(
      sessionId: sessionId,
      publicKeyHex: keyPair.publicKeyHex,
      privateKeyBytes: keyPair.privateKeyBytes,
      expiresAt: expiresAt,
    );
  }

  /// Races the LAN sweep (retried periodically — the phone may not start
  /// serving until well after the QR is shown) against the dead-drop poll;
  /// whichever delivers an encrypted blob first wins. Mirrors
  /// `VaultEditApprovalScreen._receiveViaAnyChannel`'s Completer-based race.
  Future<Map<String, dynamic>?> _awaitResult(_Session session) async {
    final blob = await _raceForBlob(session.sessionId, session.expiresAt);
    if (blob == null) return null;
    final plaintext = await _ecies.decrypt(blob, session.privateKeyBytes);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  Future<Uint8List?> _raceForBlob(String sessionId, DateTime expiresAt) {
    final completer = Completer<Uint8List?>();
    var pending = 2;

    void handle(Uint8List? result) {
      if (completer.isCompleted) return;
      if (result != null) {
        completer.complete(result);
        return;
      }
      pending--;
      if (pending == 0) completer.complete(null);
    }

    unawaited(
      _repeatUntilNotNull(
        () => _lanSweepForResult(sessionId),
        expiresAt,
        _lanRetryInterval,
      ).then(handle),
    );
    unawaited(_deadDropClient.pollUntil(sessionId, expiresAt).then(handle));

    return completer.future;
  }
}

class _Session {
  final String sessionId;
  final String publicKeyHex;
  final Uint8List privateKeyBytes;
  final DateTime expiresAt;

  const _Session({
    required this.sessionId,
    required this.publicKeyHex,
    required this.privateKeyBytes,
    required this.expiresAt,
  });

  int get expiresAtMs => expiresAt.millisecondsSinceEpoch;
}

Future<T?> _repeatUntilNotNull<T>(
  Future<T?> Function() attempt,
  DateTime expiresAt,
  Duration interval,
) async {
  while (DateTime.now().isBefore(expiresAt)) {
    final result = await attempt();
    if (result != null) return result;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) break;
    await Future<void>.delayed(remaining < interval ? remaining : interval);
  }
  return null;
}

Future<bool> _repeatUntilTrue(
  Future<bool> Function() attempt,
  DateTime expiresAt,
  Duration interval,
) async {
  while (DateTime.now().isBefore(expiresAt)) {
    if (await attempt()) return true;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) break;
    await Future<void>.delayed(remaining < interval ? remaining : interval);
  }
  return false;
}

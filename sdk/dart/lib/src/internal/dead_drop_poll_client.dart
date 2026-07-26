import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ipns_key.dart';

const _defaultGatewayUrl = 'https://ipfs.io';
const _defaultRequestTimeout = Duration(seconds: 10);
const _defaultPollInterval = Duration(seconds: 15);

/// Reads the dead-drop the mobile app publishes its cross-device response
/// to (the requester never publishes anything for sign-message/sign-request/
/// pin — only the mobile does, via `IpfsPinClient.publishDeadDrop`) — mirror
/// of `mobile/lib/services/vault_edit_dead_drop_polling_service.dart`
/// (inverted role there: the phone polls, the extension publishes).
class DeadDropPollClient {
  DeadDropPollClient({
    this.gatewayUrl = _defaultGatewayUrl,
    this.requestTimeout = _defaultRequestTimeout,
    this.pollInterval = _defaultPollInterval,
  });

  final String gatewayUrl;
  final Duration requestTimeout;
  final Duration pollInterval;

  /// A single attempt to resolve the dead-drop for [sessionIdHex]. The
  /// gateway replies `500`, not `404`, when the IPNS name hasn't propagated
  /// yet — any non-200 response or network error is treated as "not yet",
  /// never thrown.
  Future<Uint8List?> tryFetch(String sessionIdHex) async {
    final ipnsName = await deriveDeadDropIpnsName(sessionIdHex);
    final client = HttpClient();
    try {
      final url = Uri.parse(
        '$gatewayUrl/ipns/$ipnsName?cachebust=${DateTime.now().millisecondsSinceEpoch}',
      );
      final request = await client.getUrl(url).timeout(requestTimeout);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Repeats [tryFetch] every [pollInterval] until content is found or
  /// [expiresAt] passes.
  Future<Uint8List?> pollUntil(String sessionIdHex, DateTime expiresAt) async {
    while (DateTime.now().isBefore(expiresAt)) {
      final result = await tryFetch(sessionIdHex);
      if (result != null) return result;

      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(remaining < pollInterval ? remaining : pollInterval);
    }
    return null;
  }
}

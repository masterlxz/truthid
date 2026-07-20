import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

import 'vault_edit_dead_drop_ipns_key_service.dart';

const _defaultGatewayUrl = 'https://ipfs.io';
const _defaultRequestTimeout = Duration(seconds: 10);
const _defaultPollInterval = Duration(seconds: 15);

/// Lê o dead-drop cross-network publicado pela extensão pra uma proposta de
/// vault-edit (item 6 do backlog) — mirror de
/// `extension/src/session/deadDropPolling.ts::tryFetchDeadDrop`, papel
/// invertido: lá é a extensão quem lê (o Mobile publica no pareamento de
/// leitura); aqui é o celular quem lê (a extensão publica, ver
/// `extension/src/vaultEdit/deadDropPublish.ts`).
class VaultEditDeadDropPollingService {
  VaultEditDeadDropPollingService({
    this.gatewayUrl = _defaultGatewayUrl,
    this.requestTimeout = _defaultRequestTimeout,
    this.pollInterval = _defaultPollInterval,
  });

  final String gatewayUrl;
  final Duration requestTimeout;
  final Duration pollInterval;

  /// Uma tentativa de resolver o dead-drop pro `sessionId` dado. O gateway
  /// responde `500`, não `404`, quando o nome IPNS ainda não propagou —
  /// trata qualquer resposta não-200 ou erro de rede como "ainda não",
  /// nunca lança (mesma postura do lado TS).
  Future<Uint8List?> tryFetch(String sessionIdHex) async {
    final ipnsName = await computeIpnsNameForSession(sessionIdHex);
    final client = HttpClient();
    try {
      final url = Uri.parse(
        '$gatewayUrl/ipns/$ipnsName?cachebust=${DateTime.now().millisecondsSinceEpoch}',
      );
      final request = await client.getUrl(url).timeout(requestTimeout);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }
      return await consolidateHttpClientResponseBytes(response);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Repete [tryFetch] a cada [pollInterval] até achar conteúdo ou até
  /// [expiresAt] — o celular já está em primeiro plano nesta tela (é quem
  /// está esperando o QR), então não precisa do mecanismo de
  /// `chrome.alarms` que a extensão usa só pra sobreviver popup fechado/
  /// service worker suspenso.
  Future<Uint8List?> pollUntil(String sessionIdHex, DateTime expiresAt) async {
    while (DateTime.now().isBefore(expiresAt)) {
      final result = await tryFetch(sessionIdHex);
      if (result != null) return result;

      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
    return null;
  }
}

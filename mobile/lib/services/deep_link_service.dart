import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'deep_link_router.dart';

/// Ponto único de entrada dos deep links (`truthid://...`) — decide, pelo
/// `uri.host`, se é um PEDIDO novo pra aprovar (`sign-message`/`sign-request`,
/// mesmo destino do QR, via `DeepLinkRouter`).
class DeepLinkService {
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // Guard contra disparo duplo do app_links (cold-start + o primeiro evento
  // do stream às vezes entregam o mesmo URI) — pra sign-request, despachar
  // duas vezes empilharia duas telas e permitiria aprovar/executar em dobro
  // de verdade, não só um glitch visual. Vive só pela sessão do app: não
  // precisa persistir, um sessionId reaparecendo depois de reiniciado o app
  // é um pedido novo de verdade.
  final Set<String> _handledSessionIds = {};

  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) unawaited(_handle(navigatorKey, initial));

    _sub = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handle(navigatorKey, uri)),
    );
  }

  void dispose() {
    _sub?.cancel();
  }

  Future<void> _handle(GlobalKey<NavigatorState> navigatorKey, Uri uri) async {
    if (uri.scheme != 'truthid') return;

    final sessionId = uri.queryParameters['sessionId'];
    if (sessionId != null && !_handledSessionIds.add(sessionId)) return;

    final context = navigatorKey.currentState?.context;
    if (context == null) return;

    // `Uri.queryParameters` só devolve String — `v`/`expiresAt` precisam
    // virar int de novo pra baterem com o mesmo formato que o payload do QR
    // já usa (`_validatePayload` das telas de aprovação checa `is! int`).
    final payload = <String, dynamic>{
      ...uri.queryParameters,
      'action': 'truthid-${uri.host}',
      'transport': 'deeplink',
      'v': int.tryParse(uri.queryParameters['v'] ?? ''),
      'expiresAt': int.tryParse(uri.queryParameters['expiresAt'] ?? ''),
    };
    await DeepLinkRouter.handlePayload(context, payload);
  }
}

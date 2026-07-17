import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'result_delivery_channel.dart';

/// Assinatura mínima do que este canal precisa de `url_launcher` — permite
/// mockar em teste sem depender do plugin real (que precisa de platform
/// channels, indisponíveis em `flutter test` puro).
typedef LaunchUrl = Future<bool> Function(
  Uri url, {
  url_launcher.LaunchMode mode,
});

/// Transporte deep link (mesmo aparelho) — sem cifra (não há salto de rede
/// não confiável a proteger: requisitante e TruthID rodam no mesmo device,
/// no mesmo instante) e sem LAN/dead-drop (nenhum dos dois faz sentido
/// fora de rede). Só monta a URI de callback do requisitante (`callback`
/// do payload original) com os campos do `result` como query params e
/// devolve via outro deep link.
class DeepLinkDeliveryChannel implements ResultDeliveryChannel {
  final Uri callbackBaseUri;
  final LaunchUrl _launch;

  DeepLinkDeliveryChannel({
    required this.callbackBaseUri,
    LaunchUrl? launch,
  }) : _launch = launch ?? url_launcher.launchUrl;

  @override
  Future<DeliveryResult> deliver({
    required Map<String, dynamic> result,
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    final callbackUri = callbackBaseUri.replace(
      queryParameters: {
        ...callbackBaseUri.queryParameters,
        'sessionId': sessionId,
        ...result.map((key, value) => MapEntry(key, '$value')),
      },
    );

    final ok = await _launch(
      callbackUri,
      mode: url_launcher.LaunchMode.externalApplication,
    );
    if (!ok) {
      throw StateError('Could not open the callback app: $callbackUri');
    }

    return const DeliveryResult(outcome: DeliveryOutcome.sent);
  }
}

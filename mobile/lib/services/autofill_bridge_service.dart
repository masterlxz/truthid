import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deep_link_router.dart';

/// Ponte com o `TruthIdAutofillService` nativo do Android (Fase 15.5) —
/// mesmo espírito de `DeepLinkService` (`deep_link_service.dart`): um
/// método de "tem pedido pendente?" chamado no cold start (`init`) e de
/// novo toda vez que o app volta pro primeiro plano (`onResumed`).
/// `launchMode="singleTop"` faz o SO reusar a mesma `Activity` via
/// `onNewIntent` em vez de recriar quando o app já está rodando — não
/// existe, do lado nativo, um jeito simétrico de "stream" como o
/// `app_links` tem pra deep link, então o re-check no resume cobre esse
/// caso (mesmo hook de lifecycle que `AppLockGate`/`_AppLockGateState` já
/// usa, em `main.dart`).
class AutofillBridgeService {
  static const MethodChannel _channel = MethodChannel('truthid/autofill');

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) =>
      _checkAndDispatch(navigatorKey);

  Future<void> onResumed(GlobalKey<NavigatorState> navigatorKey) =>
      _checkAndDispatch(navigatorKey);

  Future<void> _checkAndDispatch(GlobalKey<NavigatorState> navigatorKey) async {
    final request = await getPendingRequest();
    if (request == null) return;

    final context = navigatorKey.currentState?.context;
    if (context == null || !context.mounted) return;

    await DeepLinkRouter.handlePayload(context, {
      'action': 'truthid-autofill-system',
      'entryType': request['entryType'],
      'requestingPackage': request['requestingPackage'],
    });
  }

  /// `null` tanto pra "nenhum pedido pendente" quanto pra "canal
  /// indisponível" (iOS, ou qualquer erro de plataforma) — mesmo
  /// fail-silent que o resto do bootstrap do app já usa pra integrações
  /// nativas opcionais.
  Future<Map<String, dynamic>?> getPendingRequest() async {
    try {
      final result = await _channel.invokeMethod('getPendingAutofillRequest');
      if (result is! Map) return null;
      return result.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// `fields` usa o vocabulário de papel de campo que o lado nativo espera
  /// (`FieldRole.name` em Kotlin — "USERNAME", "STREET_ADDRESS",
  /// "CARD_NUMBER" etc, ver `TruthIdAutofillService`/
  /// `AutofillHintClassifier.kt`) — quem decide qual valor do `VaultEntry`
  /// vai em qual papel é a tela que chama isto
  /// (`autofill_system_fill_screen.dart`), não este service.
  Future<void> submitResult(Map<String, String> fields) async {
    try {
      await _channel.invokeMethod('submitAutofillResult', fields);
    } on MissingPluginException {
      // nada a fazer — sem canal nativo, não há pra onde devolver o resultado
    } on PlatformException {
      // idem
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod('cancelAutofillRequest');
    } on MissingPluginException {
      // ver comentário em submitResult
    } on PlatformException {
      // idem
    }
  }
}

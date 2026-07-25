import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/approval_screen.dart';
import '../screens/pin_approval_screen.dart';
import '../screens/sign_message_approval_screen.dart';
import '../screens/sign_request_approval_screen.dart';
import '../screens/vault_edit_approval_screen.dart';
import '../screens/vault_session_screen.dart';
import 'app_lock_service.dart';

/// Dispatch de `payload['action']` pra tela de aprovação certa — extraído de
/// `main.dart::_openScanner` pra ser reusado tanto pelo caminho QR (depois
/// de escanear) quanto pelo deep link (`DeepLinkService`, sem escaneio
/// nenhum, o `payload` já vem parseado da URI). Mesmo dispatch, mesmas
/// telas, só a origem do `payload` muda.
class DeepLinkRouter {
  DeepLinkRouter._();

  static Future<void> handlePayload(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    // Débito M1 (code review Sessão 151): sem isso, um deep link/QR
    // empurrava a tela de aprovação por cima do AppLockGate — o overlay de
    // bloqueio é só visual, não trava o Navigator. Espera desbloquear (e
    // pede biometria proativamente) antes de despachar.
    if (AppLockService.isLockedNotifier.value) {
      AppLockService.requestAuthentication?.call();
      await _waitForUnlock();
    }
    if (!context.mounted) return;

    final action = payload['action'] as String?;

    if (action == 'truthid-auth') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ApprovalScreen(payload: payload)),
      );
    } else if (action == 'truthid-vault-session') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VaultSessionScreen(payload: payload)),
      );
    } else if (action == 'truthid-sign-message') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignMessageApprovalScreen(payload: payload),
        ),
      );
    } else if (action == 'truthid-sign-request') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignRequestApprovalScreen(payload: payload),
        ),
      );
    } else if (action == 'truthid-pin') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PinApprovalScreen(payload: payload),
        ),
      );
    } else if (action == 'truthid-vault-edit') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VaultEditApprovalScreen(payload: payload),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unrecognized request: ${action ?? "no action"}')),
      );
    }
  }

  static Future<void> _waitForUnlock() {
    final notifier = AppLockService.isLockedNotifier;
    if (!notifier.value) return Future.value();
    final completer = Completer<void>();
    late final VoidCallback listener;
    listener = () {
      if (!notifier.value) {
        notifier.removeListener(listener);
        completer.complete();
      }
    };
    notifier.addListener(listener);
    return completer.future;
  }
}

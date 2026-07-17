import 'package:flutter/material.dart';

import '../screens/approval_screen.dart';
import '../screens/sign_message_approval_screen.dart';
import '../screens/sign_request_approval_screen.dart';
import '../screens/vault_session_screen.dart';

/// Dispatch de `payload['action']` pra tela de aprovação certa — extraído de
/// `main.dart::_openScanner` pra ser reusado tanto pelo caminho QR (depois
/// de escanear) quanto pelo deep link (`DeepLinkService`, sem escaneio
/// nenhum, o `payload` já vem parseado da URI). Mesmo dispatch, mesmas
/// telas, só a origem do `payload` muda.
class DeepLinkRouter {
  DeepLinkRouter._();

  static void handlePayload(
    BuildContext context,
    Map<String, dynamic> payload,
  ) {
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unrecognized request: ${action ?? "no action"}')),
      );
    }
  }
}

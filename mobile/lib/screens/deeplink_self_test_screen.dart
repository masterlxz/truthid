import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/info_row.dart';

/// Fecha o ciclo completo do deep link (saída → entrada → aprovação →
/// entrega → callback → resultado) num único aparelho, sem precisar de um
/// segundo app requisitante real — o Practice Valuation (o app irmão que
/// motivou esta feature) é só desktop, não tem lado mobile pra testar
/// contra. Dispara `truthid://...` com `callback=truthid://
/// deeplink-test-callback`, apontando de volta pro próprio TruthID.
class DeepLinkSelfTestScreen extends StatelessWidget {
  const DeepLinkSelfTestScreen({super.key});

  Uri _buildUri(String host, Map<String, String> extra) {
    final expiresAt = DateTime.now().add(const Duration(minutes: 3));
    return Uri(
      scheme: 'truthid',
      host: host,
      queryParameters: {
        'v': '1',
        'sessionId': 'selftest-${DateTime.now().millisecondsSinceEpoch}',
        'expiresAt': '${expiresAt.millisecondsSinceEpoch}',
        'appName': 'TruthID Self-Test',
        'callback': 'truthid://deeplink-test-callback',
        ...extra,
      },
    );
  }

  Future<void> _fireSignMessage() async {
    final uri = _buildUri('sign-message', {'purpose': 'deeplink-self-test'});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _fireSignRequest() async {
    // Valores seguros e reconhecíveis — endereço "dead" convencional da
    // comunidade Ethereum, value zero, callData vazio. Não é nada que o
    // TruthID valide ou reconheça especialmente, só um destino óbvio de
    // teste.
    final uri = _buildUri('sign-request', {
      'dest': '0x000000000000000000000000000000000000dEaD',
      'value': '0',
      'callData': '0x',
      'functionSignature': 'noop()',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deep Link Self-Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Fires a truthid:// deep link at this same app, with the '
              'callback pointed back at itself — closes the full loop '
              '(request → approval → delivery → result) without needing a '
              'second app installed.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fireSignMessage,
              child: const Text(
                'Test sign-message (safe — local signature only)',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _fireSignRequest,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              child: const Text(
                'Test sign-request (real gas if you tap Approve — tap '
                'Reject to test safely)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recebe o callback do auto-teste (`truthid://deeplink-test-callback?...`)
/// e só mostra os query params crus — é exatamente o que o app requisitante
/// de verdade receberia, dá pra conferir visualmente que o formato bate.
class DeepLinkSelfTestResultScreen extends StatelessWidget {
  final Map<String, String> receivedParams;

  const DeepLinkSelfTestResultScreen({
    super.key,
    required this.receivedParams,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deep Link Self-Test — Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This is the callback the requester app would receive:',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (receivedParams.isEmpty)
              const Text(
                '(no params received)',
                style: TextStyle(color: AppColors.textMuted),
              )
            else
              ...receivedParams.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InfoRow(label: e.key, value: e.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

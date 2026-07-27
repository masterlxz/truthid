import 'package:flutter/services.dart';

import 'vault_repository.dart';

/// Ponte com o `ASCredentialIdentityStore` do iOS (Fase 15.6, fatia 1) — só
/// registra quais credenciais existem (site/usuário), pra aparecerem na
/// lista de senhas do Sistema (Ajustes > Senhas, QuickType bar). Não decifra
/// nem preenche nada: a extensão (`CredentialProviderViewController`) ainda
/// não lê o Vault (diferente do Android, que delega a decifra pro app
/// principal — a extensão iOS não consegue fazer o mesmo, ver
/// `project/PHASE.md` 15.6). Fail-silent em qualquer plataforma sem o canal
/// (Android, ou builds anteriores a este código nativo), mesmo padrão de
/// `AutofillBridgeService`.
class IosAutofillIdentityService {
  static const MethodChannel _channel = MethodChannel('truthid/ios_autofill_identities');

  Future<void> syncIdentities(List<VaultEntry> entries) async {
    final credentials = entries.where((e) => e.type == EntryType.credential).toList();
    final payload = credentials
        .map((e) => {
              'id': e.id,
              'serviceIdentifier': _hostnameOf(e.url, e.site),
              'username': e.username,
            })
        .toList();
    try {
      await _channel.invokeMethod('syncCredentialIdentities', payload);
    } on MissingPluginException {
      // Android, ou build sem o canal nativo ainda — nada a fazer.
    } on PlatformException {
      // idem
    }
  }

  // Mesmo critério de `vault_entry_form_screen.dart::_hostnameOf` (RP ID de
  // passkey) — tenta a URL, cai pro nome do site sanitizado. Duplicado de
  // propósito: aquele é privado à tela de formulário, este serviço não tem
  // acesso a ele.
  String _hostnameOf(String url, String site) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    final sanitized = site.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '');
    return sanitized.isNotEmpty ? sanitized : 'unknown';
  }
}

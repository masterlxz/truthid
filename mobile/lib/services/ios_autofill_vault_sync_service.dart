import 'dart:convert';

import 'package:flutter/services.dart';

/// Fase 15.6, fatia 2 — espelha a chave do vault e o blob cifrado
/// (`vault.enc`) pro Keychain Access Group / App Group compartilhados com a
/// extensão `AutofillExtension`, via o canal nativo
/// `truthid/ios_autofill_vault_sync` (ver `SharedVaultAccess.swift`, nos dois
/// lados). Contrato próprio — não depende do schema interno do
/// `flutter_secure_storage`. Mesmo padrão fail-silent/fire-and-forget de
/// `IosAutofillIdentityService`: Android e builds sem o canal ainda nem
/// tentam.
class IosAutofillVaultSyncService {
  static const MethodChannel _channel = MethodChannel('truthid/ios_autofill_vault_sync');

  Future<void> sync(Uint8List encryptedBlob, Uint8List vaultKey) async {
    try {
      await _channel.invokeMethod('syncVaultKey', {
        'keyBase64': base64Encode(vaultKey),
      });
      await _channel.invokeMethod('syncVaultBlob', {
        'bytes': encryptedBlob,
      });
    } on MissingPluginException {
      // Android, ou build sem o canal nativo ainda — nada a fazer.
    } on PlatformException {
      // idem
    }
  }
}

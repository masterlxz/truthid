import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ipfs_pin_client.dart';

// Config própria do Mobile pros provedores de pin — independente da do
// Desktop (não existe canal pra sincronizar API keys entre devices, ver
// PROJECT_STATE.md, Sessão 97). Mesmo padrão de storage de
// `local_storage_service.dart`/`vault_key_service.dart`.
class PinningProviderService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'vault_pinning_providers';

  Future<List<PinningProvider>> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((p) => PinningProvider.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<PinningProvider> providers) async {
    final json = jsonEncode(providers.map((p) => p.toJson()).toList());
    await _storage.write(key: _storageKey, value: json);
  }
}

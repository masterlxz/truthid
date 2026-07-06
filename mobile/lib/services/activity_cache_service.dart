import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/smart_account_activity.dart';

// Cache de progresso do SmartAccountActivityScanner — espelha
// readCache/writeCache/clearCache de useSmartAccountActivity.ts (14.10), mas
// sobre flutter_secure_storage em vez de localStorage: já é a dependência
// usada por LocalStorageService/BundlerConfigService pra persistência simples
// neste app, evita adicionar shared_preferences só pra isto.
class CachedActivity {
  final int lastScannedBlock;
  final List<SmartAccountActivity> activities;

  const CachedActivity({required this.lastScannedBlock, required this.activities});
}

class ActivityCacheService {
  final FlutterSecureStorage _storage;

  ActivityCacheService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String _key(BigInt identityId) => 'activity_cache_$identityId';

  Future<CachedActivity?> read(BigInt identityId) async {
    try {
      final raw = await _storage.read(key: _key(identityId));
      if (raw == null) return null;
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      return CachedActivity(
        lastScannedBlock: parsed['lastScannedBlock'] as int,
        activities: (parsed['activities'] as List)
            .map((a) => SmartAccountActivity.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      // JSON corrompido/de outra versão — tudo é rederivável da chain, então
      // cair pra um scan completo (fromBlock = deploy block) é seguro.
      return null;
    }
  }

  Future<void> write(
    BigInt identityId, {
    required int lastScannedBlock,
    required List<SmartAccountActivity> activities,
  }) async {
    try {
      final payload = jsonEncode({
        'lastScannedBlock': lastScannedBlock,
        'activities': activities.map((a) => a.toJson()).toList(),
      });
      await _storage.write(key: _key(identityId), value: payload);
    } catch (_) {
      // storage indisponível/cheio — o cache é só uma otimização de
      // performance, a próxima visita simplesmente reescaneia mais devagar.
    }
  }

  Future<void> clear(BigInt identityId) async {
    try {
      await _storage.delete(key: _key(identityId));
    } catch (_) {
      // ignore
    }
  }
}

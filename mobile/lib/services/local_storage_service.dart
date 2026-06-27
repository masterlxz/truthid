import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyIdentityId = 'paired_identity_id';

  // Só guardamos o identityId. O contrato IdentityRegistry não tem um getter
  // de id -> username (só username -> id), então não tem como o mobile
  // resolver o @username sozinho sem o desktop empurrar essa informação
  // por algum canal ao vivo — que é exatamente o que estamos eliminando.
  Future<void> savePairedIdentity(String identityId) async {
    await _storage.write(key: _keyIdentityId, value: identityId);
  }

  Future<String?> getPairedIdentityId() async {
    return _storage.read(key: _keyIdentityId);
  }

  Future<void> clearPairedIdentity() async {
    await _storage.delete(key: _keyIdentityId);
  }
}

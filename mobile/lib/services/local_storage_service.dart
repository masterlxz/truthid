import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyIdentityId = 'paired_identity_id';
  static const _keyUsername = 'paired_username';

  Future<void> savePairedIdentity({
    required String identityId,
    required String username,
  }) async {
    await _storage.write(key: _keyIdentityId, value: identityId);
    await _storage.write(key: _keyUsername, value: username);
  }

  // Record: retorna dois valores nomeados de uma vez, ou null se não tiver nada salvo.
  // ({String identityId, String username}) é como uma namedtuple do Python.
  Future<({String identityId, String username})?> getPairedIdentity() async {
    final id = await _storage.read(key: _keyIdentityId);
    final username = await _storage.read(key: _keyUsername);
    if (id == null || username == null) return null;
    return (identityId: id, username: username);
  }

  Future<void> clearPairedIdentity() async {
    await _storage.delete(key: _keyIdentityId);
    await _storage.delete(key: _keyUsername);
  }
}

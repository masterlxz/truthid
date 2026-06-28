import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyIdentityId = 'paired_identity_id';
  static const _keyUsername = 'paired_username';

  Future<void> savePairedIdentity(String identityId) async {
    await _storage.write(key: _keyIdentityId, value: identityId);
  }

  Future<String?> getPairedIdentityId() async {
    return _storage.read(key: _keyIdentityId);
  }

  Future<void> savePairedUsername(String username) async {
    await _storage.write(key: _keyUsername, value: username);
  }

  Future<String?> getPairedUsername() async {
    return _storage.read(key: _keyUsername);
  }

  Future<void> clearPairedIdentity() async {
    await _storage.delete(key: _keyIdentityId);
    await _storage.delete(key: _keyUsername);
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Bloqueio de app via biometria/PIN/padrão/senha **do dispositivo** — nunca
/// um segredo novo gerenciado pelo TruthID. `authenticate()` delega pro SO
/// (`biometricOnly: false` deixa o Android/iOS decidir o método e cair pro
/// PIN/padrão/senha automaticamente se a biometria falhar ou não estiver
/// configurada).
class AppLockService {
  static const _keyEnabled = 'app_lock_enabled';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  AppLockService({FlutterSecureStorage? storage, LocalAuthentication? localAuth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = localAuth ?? LocalAuthentication();

  Future<bool> isEnabled() async {
    return (await _storage.read(key: _keyEnabled)) == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await _storage.write(key: _keyEnabled, value: enabled.toString());
  }

  /// `false` se o device não tem biometria nem PIN/padrão/senha configurados
  /// — usado pra não deixar habilitar o bloqueio e trancar o usuário fora.
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  Future<bool> authenticate() => _auth.authenticate(
        localizedReason: 'Unlock TruthID',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
}

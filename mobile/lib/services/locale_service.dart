import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Idioma escolhido manualmente pelo usuário no seletor de Settings.
/// `null` = segue o idioma do sistema (comportamento padrão até o usuário
/// abrir o seletor pela primeira vez).
class LocaleService {
  static const _keyLocale = 'truthid_language';

  /// Consumido via `ValueListenableBuilder` em `TruthIDApp` — muda na hora
  /// que o usuário escolhe um idioma no seletor, sem precisar reiniciar o
  /// app (mesmo padrão de `AppLockService.isLockedNotifier`).
  static final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('pt', 'BR'),
    Locale('es'),
    Locale('zh', 'CN'),
  ];

  final FlutterSecureStorage _storage;

  LocaleService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Locale? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('_');
    return Locale(parts[0], parts.length > 1 ? parts[1] : null);
  }

  String _encode(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';

  /// Lê a preferência salva e já popula `localeNotifier` — chamar uma vez
  /// no boot, antes do primeiro `runApp`, pra não piscar no idioma errado.
  Future<void> loadSavedLocale() async {
    final raw = await _storage.read(key: _keyLocale);
    localeNotifier.value = _decode(raw);
  }

  Future<void> setLocale(Locale? locale) async {
    localeNotifier.value = locale;
    if (locale == null) {
      await _storage.delete(key: _keyLocale);
    } else {
      await _storage.write(key: _keyLocale, value: _encode(locale));
    }
  }
}

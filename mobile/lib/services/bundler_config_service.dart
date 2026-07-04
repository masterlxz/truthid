import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/secrets.dart';

// Chaves usadas no flutter_secure_storage pra persistir a configuracao do
// bundler. Usuario pode configurar via SettingsScreen; se nao configurar,
// o fallback eh o secrets.dart (backward compat, util pro dev).
const _kApiKeyKey = 'bundler_api_key';
const _kNetworkKey = 'bundler_network';

class BundlerConfig {
  final String apiKey;
  final String network;

  const BundlerConfig({required this.apiKey, required this.network});
}

class BundlerConfigService {
  final FlutterSecureStorage _storage;

  BundlerConfigService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Le a configuracao do bundler. Prioridade:
  // 1. storage (configurado pelo usuario via SettingsScreen)
  // 2. secrets.dart (fallback de compilacao — backward compat)
  Future<BundlerConfig> getConfig() async {
    final apiKey = await _storage.read(key: _kApiKeyKey);
    final network = await _storage.read(key: _kNetworkKey);

    return BundlerConfig(
      apiKey: (apiKey != null && apiKey.isNotEmpty) ? apiKey : pimlicoApiKey,
      network: (network != null && network.isNotEmpty) ? network : 'base',
    );
  }

  // Salva a configuracao do usuario (SettingsScreen).
  Future<void> saveConfig({required String apiKey, required String network}) async {
    await _storage.write(key: _kApiKeyKey, value: apiKey);
    await _storage.write(key: _kNetworkKey, value: network);
  }
}
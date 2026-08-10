import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'arweave_isolate.dart';
import 'arweave_jwk.dart' as arweave_jwk;

// Carrega/gera/guarda a wallet Arweave (JWK) local — mesmo padrão de
// device_key_service.dart (um serviço dedicado, sem abstração de "keyring"
// compartilhada; cada tipo de segredo instancia seu próprio
// FlutterSecureStorage). Espelha o par get_arweave_wallet/set_arweave_wallet
// de lib.rs (Desktop, backing no OS keyring) — aqui o backing é o
// keystore/keychain nativo via flutter_secure_storage.
class ArweaveWalletService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'truthid_arweave_wallet_jwk';

  Future<String?> _readRaw() => _storage.read(key: _storageKey);

  Future<bool> exists() async => (await _readRaw()) != null;

  // Carrega a wallet local — erro claro se ausente, sem fallback (mesmo
  // padrão de corte direto já usado no Desktop pra publicação no Arweave).
  Future<arweave_jwk.ArweaveJwk> load() async {
    final json = await _readRaw();
    if (json == null) {
      throw Exception(
          'nenhuma wallet Arweave configurada — gere ou importe uma antes de publicar');
    }
    return arweave_jwk.parseJwk(json);
  }

  Future<String> address() async {
    final jwk = await load();
    return arweave_jwk.walletAddress(jwk);
  }

  // Gera uma wallet nova e substitui a atual. Keygen RSA-4096 roda em
  // isolate dedicado (generateJwkInIsolate) — lenta (segundos) e travaria
  // a UI se rodasse inline.
  Future<String> generate() async {
    final jwk = await generateJwkInIsolate();
    final address = arweave_jwk.walletAddress(jwk);
    await _storage.write(key: _storageKey, value: jsonEncode(jwk.toJson()));
    return address;
  }

  // Importa uma wallet existente (JWK em JSON) — parseJwk já valida
  // consistência matemática dos componentes antes de gravar.
  Future<String> import(String jwkJson) async {
    final jwk = arweave_jwk.parseJwk(jwkJson);
    final address = arweave_jwk.walletAddress(jwk);
    await _storage.write(key: _storageKey, value: jwkJson);
    return address;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'blockchain_service.dart';
import 'device_key_service.dart';
import 'ecies_service.dart';
import 'hkdf_util.dart';

class VaultKeyService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'truthid_vault_key';
  static const _legacySalt = 'TruthID';
  static const _legacyInfo = 'vault-key-v1';
  static const _walletSalt = 'TruthID';
  static const _walletInfo = 'vault-key-v2';

  final DeviceKeyService _deviceKeyService;
  final EciesService _ecies;

  VaultKeyService({DeviceKeyService? deviceKeyService, EciesService? ecies})
      : _deviceKeyService = deviceKeyService ?? DeviceKeyService(),
        _ecies = ecies ?? EciesService();

  Future<Uint8List> deriveVaultKey() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null) {
      return Uint8List.fromList(base64Decode(stored));
    }

    return _deriveLegacyKey();
  }

  Future<bool> hasVaultKey() async {
    return await _storage.read(key: _storageKey) != null;
  }

  Future<void> decryptVaultKeyFromPairing(Uint8List encryptedBlob) async {
    final devicePrivBytes = await _deviceKeyService.getPrivateKeyBytes();
    final plaintext = await _ecies.decrypt(encryptedBlob, devicePrivBytes);

    await _storage.write(
      key: _storageKey,
      value: base64Encode(plaintext),
    );
  }

  // A vault key cifrada (ECIES) é gravada on-chain durante o registerDevice
  // e fica lá pra sempre em deviceVaultKeys — não é um dado transiente que só
  // existe durante a janela do pareamento. Isso permite tentar de novo a
  // qualquer momento (ex: app foi derrubado em background antes de terminar
  // a decifra na 1a tentativa) sem precisar revogar e parear o device de novo.
  // Retorna false (sem lançar) se ainda não há nada on-chain pra decifrar.
  Future<bool> tryRecoverFromChain(BlockchainService blockchain) async {
    final address = await _deviceKeyService.getDeviceAddress();
    final encryptedKey = await blockchain.getDeviceVaultKey(address);
    if (encryptedKey == null) return false;

    try {
      await decryptVaultKeyFromPairing(encryptedKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Deriva a vault key a partir de uma assinatura `personal_sign` da wallet
  // externa (via WalletConnect, P68 fatia 1) sobre a mensagem fixa
  // "TruthID Vault Key v1" — mesmo HKDF que `derive_vault_key_from_wallet`
  // já faz no Rust do Desktop (`desktop/src-tauri/src/lib.rs:262-275`, salt
  // "TruthID", info "vault-key-v2"), mas persistido (diferente da derivação
  // legada acima, que nunca grava em disco). Como wallets modernas assinam
  // de forma determinística (RFC 6979), a mesma wallet + mesma mensagem
  // produz sempre a mesma assinatura — e portanto a mesma chave — em
  // qualquer device, mesmo sem ter passado por pareamento nenhum.
  Future<void> deriveAndStoreFromWalletSignature({
    required Uint8List r,
    required Uint8List s,
    required int v,
  }) async {
    final ikm = Uint8List.fromList([...r, ...s, v]);
    final key = hkdfSha256(
      ikm: ikm,
      salt: utf8.encode(_walletSalt),
      info: utf8.encode(_walletInfo),
      length: 32,
    );

    await _storage.write(key: _storageKey, value: base64Encode(key));
  }

  Future<Uint8List> _deriveLegacyKey() async {
    final ikm = await _deviceKeyService.getPrivateKeyBytes();
    return hkdfSha256(
      ikm: ikm,
      salt: utf8.encode(_legacySalt),
      info: utf8.encode(_legacyInfo),
      length: 32,
    );
  }
}

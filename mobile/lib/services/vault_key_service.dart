import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:elliptic/elliptic.dart';
import 'package:elliptic/ecdh.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_key_service.dart';

class VaultKeyService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'truthid_vault_key';
  static const _legacySalt = 'TruthID';
  static const _legacyInfo = 'vault-key-v1';

  final DeviceKeyService _deviceKeyService;
  final _ec = getSecp256k1();

  VaultKeyService({DeviceKeyService? deviceKeyService})
      : _deviceKeyService = deviceKeyService ?? DeviceKeyService();

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
    if (encryptedBlob.length < 33 + 12 + 16) {
      throw Exception('encryptedBlob too short');
    }

    final ephemeralPubBytes = encryptedBlob.sublist(0, 33);
    final nonceBytes = encryptedBlob.sublist(33, 45);
    final ciphertext = encryptedBlob.sublist(45);

    final devicePrivBytes = await _deviceKeyService.getPrivateKeyBytes();

    // ECDH via elliptic package
    final devicePriv = PrivateKey.fromBytes(_ec, devicePrivBytes);
    final ephemeralPub = PublicKey.fromHex(_ec, _bytesToHex(ephemeralPubBytes));
    final sharedSecretBytes = computeSecret(devicePriv, ephemeralPub);
    final sharedSecret = Uint8List.fromList(sharedSecretBytes);

    // Derive AES-256 key via SHA-256(shared_secret)
    final aesKey = crypto.sha256.convert(sharedSecret).bytes;

    // AES-256-GCM decryption via cryptography package
    final cipher = crypt.AesGcm.with256bits();
    final secretKey = crypt.SecretKey(aesKey);
    final secretBox = crypt.SecretBox(
      ciphertext,
      nonce: nonceBytes,
      mac: crypt.Mac.empty,
    );
    final plaintext = await cipher.decrypt(secretBox, secretKey: secretKey);

    await _storage.write(
      key: _storageKey,
      value: base64Encode(plaintext),
    );
  }

  Future<Uint8List> _deriveLegacyKey() async {
    final ikm = await _deviceKeyService.getPrivateKeyBytes();
    return _hkdfSha256(
      ikm: ikm,
      salt: utf8.encode(_legacySalt),
      info: utf8.encode(_legacyInfo),
      length: 32,
    );
  }

  static Uint8List _hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    assert(length <= 32, 'length must be <= 32 for single-block HKDF');

    final prk = crypto.Hmac(crypto.sha256, salt).convert(ikm).bytes;
    final t1 = crypto.Hmac(crypto.sha256, prk).convert([...info, 0x01]).bytes;

    return Uint8List.fromList(t1.sublist(0, length));
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
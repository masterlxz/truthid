import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'device_key_service.dart';

// Deriva a chave AES-256 do vault a partir da chave privada do device
// usando HKDF-SHA256 (RFC 5869).
//
// A chave derivada é determinística: mesmo device → mesmo resultado, sempre.
// Ela nunca é persistida — é rederivada a cada uso a partir da chave no
// secure storage.
class VaultKeyService {
  final DeviceKeyService _deviceKeyService;

  VaultKeyService({DeviceKeyService? deviceKeyService})
      : _deviceKeyService = deviceKeyService ?? DeviceKeyService();

  static const _salt = 'TruthID';
  static const _info = 'vault-key-v1';

  Future<Uint8List> deriveVaultKey() async {
    final ikm = await _deviceKeyService.getPrivateKeyBytes();
    return _hkdfSha256(
      ikm: ikm,
      salt: utf8.encode(_salt),
      info: utf8.encode(_info),
      length: 32,
    );
  }

  // HKDF-SHA256 (RFC 5869) para length <= 32 bytes (um único bloco de expand).
  static Uint8List _hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    assert(length <= 32, 'length must be <= 32 for single-block HKDF');

    // Passo 1 — Extract: PRK = HMAC-SHA256(salt, IKM)
    final prk = Hmac(sha256, salt).convert(ikm).bytes;

    // Passo 2 — Expand: T(1) = HMAC-SHA256(PRK, info || 0x01)
    final t1 = Hmac(sha256, prk).convert([...info, 0x01]).bytes;

    return Uint8List.fromList(t1.sublist(0, length));
  }
}

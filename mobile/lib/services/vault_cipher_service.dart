import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_key_service.dart';

// Cifra e decifra o vault local com AES-256-GCM.
//
// Formato do blob: nonce(12) || ciphertext || tag(16)
// Compatível com o vault.rs do desktop (mesmo esquema de bytes).
//
// A chave nunca é persistida — rederivada via VaultKeyService a cada uso.
class VaultCipherService {
  final VaultKeyService _keyService;
  final _algorithm = AesGcm.with256bits();

  VaultCipherService({VaultKeyService? keyService})
      : _keyService = keyService ?? VaultKeyService();

  Future<Uint8List> encrypt(Uint8List plaintext) async {
    final keyBytes = await _keyService.deriveVaultKey();
    final secretKey = SecretKey(keyBytes);

    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
    );

    // nonce(12) || ciphertext || tag(16)
    return Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  Future<Uint8List> decrypt(Uint8List blob) async {
    // mínimo: 12 nonce + 16 tag
    if (blob.length < 28) {
      throw ArgumentError('vault blob too short: ${blob.length} bytes');
    }

    final nonce = blob.sublist(0, 12);
    final mac = blob.sublist(blob.length - 16);
    final ciphertext = blob.sublist(12, blob.length - 16);

    final keyBytes = await _keyService.deriveVaultKey();
    final secretKey = SecretKey(keyBytes);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

    final plaintext = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    return Uint8List.fromList(plaintext);
  }
}

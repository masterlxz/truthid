import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf.dart';

/// Symmetric cipher for a `vault-edit` proposal (P27) — mirrors
/// `pin_content_cipher.dart`'s phase-1 push cipher, same reasoning (neither
/// side has the other's public key yet, so a key derived deterministically
/// from `sessionId` via HKDF is used instead). Domain-separated from
/// `/pin`'s content cipher by salt — must match
/// `extension/src/vaultEdit/cipher.ts` and
/// `mobile/lib/services/vault_edit_content_cipher_service.dart` byte-for-byte.
const _vaultEditContentHkdfSalt = 'TruthID Vault Edit Content';
const _vaultEditContentHkdfInfo = 'content-key-v1';

/// Derives the vault-edit content AES-256 key from the `sessionId` (hex).
Uint8List deriveVaultEditContentKey(String sessionIdHex) {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  return hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_vaultEditContentHkdfSalt),
    info: utf8.encode(_vaultEditContentHkdfInfo),
    length: 32,
  );
}

/// Encrypts [plaintext] in the format the Device's vault-edit receiver
/// expects: `nonce(12) || ciphertext || tag(16)` (AES-256-GCM) — same wire
/// format as `/pin`'s content cipher, different key.
Future<Uint8List> encryptVaultEditContent(Uint8List plaintext, Uint8List key) async {
  final secretKey = SecretKey(key);
  final secretBox = await AesGcm.with256bits().encrypt(
    plaintext,
    secretKey: secretKey,
  );
  return Uint8List.fromList([
    ...secretBox.nonce,
    ...secretBox.cipherText,
    ...secretBox.mac.bytes,
  ]);
}

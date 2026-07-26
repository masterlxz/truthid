import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf.dart';

/// Symmetric cipher for the content pushed by the requester in phase 1 of
/// `/pin` (see `mobile/lib/services/pin_content_cipher_service.dart`).
/// Neither side has the other's public key at this point (the requester
/// built the QR before the phone was ever involved) — resolved with a
/// symmetric key derived deterministically from `sessionId` via HKDF, the
/// same pattern `ipns_key.dart` uses. Never reuse the IPNS derivation's
/// salt/info here — different context, domain separation.
const _pinContentHkdfSalt = 'TruthID Pin Content';
const _pinContentHkdfInfo = 'content-key-v1';

/// Derives the phase-1 AES-256 key from the `sessionId` (hex).
Uint8List derivePinContentKey(String sessionIdHex) {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  return hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_pinContentHkdfSalt),
    info: utf8.encode(_pinContentHkdfInfo),
    length: 32,
  );
}

/// Encrypts [plaintext] in the format the mobile app's phase 1 receiver
/// expects: `nonce(12) || ciphertext || tag(16)` (AES-256-GCM).
Future<Uint8List> encryptPinContent(Uint8List plaintext, Uint8List key) async {
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

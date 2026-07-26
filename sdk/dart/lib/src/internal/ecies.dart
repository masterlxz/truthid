import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:elliptic/ecdh.dart';
import 'package:elliptic/elliptic.dart';

/// Generic ECIES (secp256k1 ECDH + SHA-256 + AES-256-GCM) — same algorithm
/// and blob format as `mobile/lib/services/ecies_service.dart`:
///
///   ephemeral_pubkey (33 bytes, compressed) || nonce (12 bytes) || ciphertext + tag
///
/// The AES key is always `SHA-256(ECDH secret)`, never the raw secret.
/// `decrypt` is what `TruthIDRequester` uses to read the mobile's encrypted
/// response — the mobile always generates a fresh ephemeral keypair per
/// message and prepends its public key to the blob; the requester supplies
/// its own long-lived-for-the-session private key (the one whose public half
/// went into the QR).
class EciesService {
  final _ec = getSecp256k1();

  Future<Uint8List> encrypt(
    Uint8List plaintext,
    String recipientPubKeyHex,
  ) async {
    final recipientPub = _parsePublicKey(recipientPubKeyHex);

    final ephemeralPriv = _ec.generatePrivateKey();
    final ephemeralPub = ephemeralPriv.publicKey;

    final aesKey = _deriveAesKey(ephemeralPriv, recipientPub);

    final cipher = crypt.AesGcm.with256bits();
    final secretKey = crypt.SecretKey(aesKey);
    final nonce = cipher.newNonce();
    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final blob = BytesBuilder();
    blob.add(_hexToBytes(ephemeralPub.toCompressedHex()));
    // concatenation() = nonce || ciphertext || tag.
    blob.add(secretBox.concatenation());
    return blob.toBytes();
  }

  Future<Uint8List> decrypt(
    Uint8List blob,
    Uint8List recipientPrivateKeyBytes,
  ) async {
    if (blob.length < 33 + 12 + 16) {
      throw ArgumentError('blob too short to be a valid ECIES payload');
    }

    final ephemeralPubBytes = blob.sublist(0, 33);
    final rest = blob.sublist(33);

    final recipientPriv = PrivateKey.fromBytes(_ec, recipientPrivateKeyBytes);
    final ephemeralPub = PublicKey.fromHex(_ec, _bytesToHex(ephemeralPubBytes));

    final aesKey = _deriveAesKey(recipientPriv, ephemeralPub);

    final cipher = crypt.AesGcm.with256bits();
    final secretKey = crypt.SecretKey(aesKey);
    final secretBox = crypt.SecretBox.fromConcatenation(
      rest,
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await cipher.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(plaintext);
  }

  /// Generates a fresh secp256k1 keypair for a request session — the private
  /// key stays with the caller (never sent anywhere), the public key
  /// (compressed hex) goes into the QR payload as `ephemeralPubKey`.
  ({Uint8List privateKeyBytes, String publicKeyHex}) generateKeyPair() {
    final priv = _ec.generatePrivateKey();
    return (
      privateKeyBytes: Uint8List.fromList(priv.bytes),
      publicKeyHex: priv.publicKey.toCompressedHex(),
    );
  }

  PublicKey _parsePublicKey(String pubKeyHex) {
    final hex =
        pubKeyHex.startsWith('0x') ? pubKeyHex.substring(2) : pubKeyHex;
    if (hex.length != 66 && hex.length != 130) {
      throw ArgumentError(
        'pubKeyHex must be 33-byte (compressed) or 65-byte (uncompressed) secp256k1 key',
      );
    }
    return PublicKey.fromHex(_ec, hex);
  }

  Uint8List _deriveAesKey(PrivateKey selfPriv, PublicKey otherPub) {
    final sharedSecret = Uint8List.fromList(computeSecret(selfPriv, otherPub));
    return Uint8List.fromList(crypto.sha256.convert(sharedSecret).bytes);
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

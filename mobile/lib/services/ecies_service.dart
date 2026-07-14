import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:elliptic/ecdh.dart';
import 'package:elliptic/elliptic.dart';

/// ECIES genérico (secp256k1 ECDH + SHA-256 + AES-256-GCM) para cifrar dados
/// para qualquer destinatário que só tenha uma chave pública — não é sobre a
/// chave simétrica do vault em si (ver [VaultKeyService] para isso), é o
/// primitivo usado, por exemplo, para entregar um subconjunto do vault para a
/// chave efêmera de uma sessão de extensão de navegador (13.9).
///
/// Formato do blob, idêntico ao `encrypt_bytes_for_device` em
/// `desktop/src-tauri/src/lib.rs`:
///   ephemeral_pubkey(33 bytes comprimida) || nonce(12 bytes) || ciphertext+tag
///
/// A chave AES é sempre `SHA-256(segredo ECDH)`, nunca o segredo cru — a
/// Sessão 92 documentou o bug real de esquecer esse hash (toda vault key
/// entregue via pareamento falhava a decifra com erro de MAC).
///
/// Achado nesta sessão (13.9): `SecretBox(ciphertext, mac: Mac.empty)` com o
/// tag já concatenado ao ciphertext **não decifra nunca** — o pacote
/// `cryptography` recalcula o MAC sobre `secretBox.cipherText` inteiro e
/// compara contra `secretBox.mac`; passando `Mac.empty` (0 bytes) essa
/// comparação falha sempre, com o mesmo erro de MAC que o bug da Sessão 92,
/// mas por um motivo diferente. A API certa pra "nonce+ciphertext+tag
/// concatenados" é `SecretBox.fromConcatenation`. Achado ao escrever o
/// primeiro teste de round-trip real do lado Dart — o decrypt "funcionava"
/// antes só porque nunca tinha sido exercitado de ponta a ponta em runtime
/// (o teste Rust da Sessão 92 reimplementa o decrypt em Rust, não chama o
/// Dart real).
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
    // concatenation() = nonce || ciphertext || tag — exatamente o formato
    // que o resto do blob espera depois da chave pública efêmera.
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
    // nonce(12) || ciphertext || tag(16) — o que SecretBox.fromConcatenation
    // espera.
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

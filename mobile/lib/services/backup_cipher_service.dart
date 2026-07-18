import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// Backup criptografado exportável do Vault (item 4 do roadmap pós-Fase 14).
//
// Diferente do resto do Vault (chave sempre derivada da assinatura da
// wallet, ver VaultCipherService/VaultKeyService), o backup usa uma senha de
// exportação separada, escolhida pelo usuário — restaurar não deve exigir
// ter a wallet em mãos.
//
// Formato do envelope (idêntico ao Rust, desktop/src-tauri/src/backup.rs):
// magic(8) || salt(16) || kdf_iterations(4, big-endian u32) || nonce(12) ||
// ciphertext+tag(AES-256-GCM). O iteration count viaja dentro do arquivo.
const String backupMagic = 'TIDVLTB1';
const int backupKdfIterations = 600000;

const int _saltLen = 16;
const int _nonceLen = 12;
const int _headerLen = 8 + _saltLen + 4 + _nonceLen;

class BackupCipherService {
  final _algorithm = AesGcm.with256bits();

  Future<Uint8List> encrypt(Uint8List plaintext, String password) async {
    final salt = _randomBytes(_saltLen);
    final nonce = _randomBytes(_nonceLen);
    return encryptWith(
      plaintext,
      password,
      salt: salt,
      nonce: nonce,
      iterations: backupKdfIterations,
    );
  }

  // Núcleo testável — recebe salt/nonce/iterations explícitos. Produção usa
  // encrypt() (aleatório); o vetor fixo cruzado com o Rust chama isto direto.
  Future<Uint8List> encryptWith(
    Uint8List plaintext,
    String password, {
    required Uint8List salt,
    required Uint8List nonce,
    required int iterations,
  }) async {
    final secretKey = await _deriveKey(password, salt, iterations);
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    final header = ByteData(4)..setUint32(0, iterations, Endian.big);
    return Uint8List.fromList([
      ...utf8.encode(backupMagic),
      ...salt,
      ...header.buffer.asUint8List(),
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  Future<Uint8List> decrypt(Uint8List blob, String password) async {
    if (blob.length < _headerLen + 16) {
      throw const FormatException('backup file too short or corrupted');
    }
    // Compara bytes crus, não via utf8.decode — um arquivo corrompido pode
    // ter bytes que não formam UTF-8 válido nos primeiros 8 bytes, o que
    // lançaria uma FormatException genérica do próprio utf8.decode antes de
    // chegarmos aqui, mascarando o motivo real.
    if (!_bytesEqual(blob.sublist(0, 8), utf8.encode(backupMagic))) {
      throw const FormatException('not a TruthID backup file (bad magic)');
    }
    final salt = blob.sublist(8, 8 + _saltLen);
    final iterations = ByteData.sublistView(
      blob,
      8 + _saltLen,
      _headerLen - _nonceLen,
    ).getUint32(0, Endian.big);
    final nonce = blob.sublist(_headerLen - _nonceLen, _headerLen);
    final rest = blob.sublist(_headerLen);
    final mac = rest.sublist(rest.length - 16);
    final ciphertext = rest.sublist(0, rest.length - 16);

    final secretKey = await _deriveKey(password, salt, iterations);
    try {
      final plaintext = await _algorithm.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const FormatException('wrong password or corrupted backup file');
    }
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

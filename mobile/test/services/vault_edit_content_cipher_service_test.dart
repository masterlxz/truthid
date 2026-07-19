import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/vault_edit_content_cipher_service.dart';
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;

void main() {
  const sessionIdHex = '000102030405060708090a0b0c0d0e0f';

  test('deriveVaultEditContentKey é determinístico e sempre tem 32 bytes',
      () async {
    final a = deriveVaultEditContentKey(sessionIdHex);
    final b = deriveVaultEditContentKey(sessionIdHex);
    expect(a, b);
    expect(a.length, 32);
  });

  test('sessionIds diferentes derivam chaves diferentes', () async {
    final a = deriveVaultEditContentKey(sessionIdHex);
    final b = deriveVaultEditContentKey('0f0e0d0c0b0a09080706050403020100');
    expect(a, isNot(b));
  });

  test('encrypt+decrypt faz round-trip com o conteúdo original', () async {
    final key = deriveVaultEditContentKey(sessionIdHex);
    final plaintext =
        Uint8List.fromList(utf8.encode('{"site":"example.com"}'));

    final blob = await encryptVaultEditContent(plaintext, key);
    final decrypted = await decryptVaultEditContent(blob, key);

    expect(decrypted, plaintext);
  });

  test('decrypt com a chave errada lança FormatException', () async {
    final key = deriveVaultEditContentKey(sessionIdHex);
    final wrongKey = deriveVaultEditContentKey('0f0e0d0c0b0a09080706050403020100');
    final blob = await encryptVaultEditContent(
      Uint8List.fromList([1, 2, 3]),
      key,
    );

    expect(
      () => decryptVaultEditContent(blob, wrongKey),
      throwsA(isA<FormatException>()),
    );
  });

  test('decrypt de um blob corrompido lança FormatException', () async {
    final key = deriveVaultEditContentKey(sessionIdHex);
    final blob = await encryptVaultEditContent(
      Uint8List.fromList([1, 2, 3]),
      key,
    );
    blob[blob.length - 1] ^= 0xff; // corrompe o último byte do MAC

    expect(
      () => decryptVaultEditContent(blob, key),
      throwsA(isA<FormatException>()),
    );
  });

  test('decrypt de um blob curto demais lança FormatException', () async {
    final key = deriveVaultEditContentKey(sessionIdHex);
    expect(
      () => decryptVaultEditContent(Uint8List.fromList([1, 2, 3]), key),
      throwsA(isA<FormatException>()),
    );
  });

  group('vetor fixo cross-plataforma (gerado com extension/src/vaultEdit/'
      'cipher.ts via @noble/hashes/hkdf, não só round-trip interno — mesmo '
      'padrão que pegou o bug do ECIES na Sessão 92)', () {
    // Chave derivada pela implementação TS real (hkdf + sha256 do
    // @noble/hashes) pro mesmo sessionId/salt/info — prova que o HKDF do
    // pacote `crypto` (Dart) bate byte-a-byte com o `@noble/hashes` (TS).
    const expectedKeyHex =
        'decf3ae12fdb6a1287a484ea91f73bb81b1924f78250fbb65ef717d82d3c53a2';

    // Blob cifrado pela implementação TS real (Web Crypto AES-256-GCM, nonce
    // fixo só pra reprodutibilidade do vetor — nunca reusar um nonce fixo em
    // produção) do plaintext `{"site":"example.com","username":"alice"}`.
    const fixedBlobHex =
        '07070707070707070707070777a166930f33513f39e7bec8cad31347f4211937'
        '116ef217da7ade060bde633fe20eb5f8b8d34fd59f66ffe1f6a62fbc6b3afb941'
        'f2cd0a398';
    const expectedPlaintext = '{"site":"example.com","username":"alice"}';

    test('deriveVaultEditContentKey bate byte-a-byte com o HKDF da extensão',
        () {
      final key = deriveVaultEditContentKey(sessionIdHex);
      expect(bytesToHex(key, include0x: false), expectedKeyHex);
    });

    test('decrypt de um blob cifrado pela extensão devolve o mesmo plaintext',
        () async {
      final key = deriveVaultEditContentKey(sessionIdHex);
      final blob = hexToBytes(fixedBlobHex);

      final decrypted = await decryptVaultEditContent(blob, key);

      expect(utf8.decode(decrypted), expectedPlaintext);
    });
  });
}

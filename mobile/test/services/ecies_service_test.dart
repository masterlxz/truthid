import 'dart:convert';
import 'dart:typed_data';

import 'package:elliptic/elliptic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/ecies_service.dart';

void main() {
  late EciesService ecies;

  setUp(() {
    ecies = EciesService();
  });

  group('encrypt/decrypt round-trip (auto)', () {
    // Sanity check interno: só prova que encrypt+decrypt são inversos entre
    // si. NÃO pega descompasso entre linguagens (ex: um lado esquecer o
    // SHA-256 do segredo ECDH, ou o formato do blob divergir do Rust) — só o
    // vetor cruzado fixo abaixo prova isso.
    test('decrypt(encrypt(x)) retorna x', () async {
      final recipientPriv = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final recipientPub = await _publicKeyHexFor(recipientPriv);
      final plaintext = utf8.encode('hello from the vault');

      final blob = await ecies.encrypt(
        Uint8List.fromList(plaintext),
        recipientPub,
      );
      final decrypted = await ecies.decrypt(blob, recipientPriv);

      expect(utf8.decode(decrypted), 'hello from the vault');
    });

    test('cada chamada de encrypt usa uma chave efêmera diferente', () async {
      final recipientPriv = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final recipientPub = await _publicKeyHexFor(recipientPriv);
      final plaintext = Uint8List.fromList(utf8.encode('same input'));

      final blobA = await ecies.encrypt(plaintext, recipientPub);
      final blobB = await ecies.encrypt(plaintext, recipientPub);

      expect(blobA, isNot(equals(blobB)));
    });

    test('decrypt falha com a chave privada errada', () async {
      final recipientPriv = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final wrongPriv = Uint8List.fromList(List.generate(32, (i) => i + 2));
      final recipientPub = await _publicKeyHexFor(recipientPriv);
      final blob = await ecies.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        recipientPub,
      );

      expect(() => ecies.decrypt(blob, wrongPriv), throwsA(anything));
    });

    test('aceita chave pública em formato não-comprimido (65 bytes)', () async {
      final recipientPriv = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final recipientPubUncompressed =
          await _publicKeyHexFor(recipientPriv, compressed: false);
      final plaintext = Uint8List.fromList(utf8.encode('uncompressed pubkey'));

      final blob = await ecies.encrypt(plaintext, recipientPubUncompressed);
      final decrypted = await ecies.decrypt(blob, recipientPriv);

      expect(utf8.decode(decrypted), 'uncompressed pubkey');
    });
  });

  group('vetor cruzado fixo — interoperabilidade com Rust/JS', () {
    // Gerado uma vez rodando o EciesService.encrypt real do Dart contra uma
    // chave privada de teste determinística (SHA-256 de uma string fixa) —
    // ver desktop/src-tauri/src/lib.rs::dart_produced_blob_decrypts_correctly
    // pro mesmo vetor decifrado em Rust, e extension/src/crypto/ecies.test.ts
    // pro mesmo vetor decifrado em JS. Os três decifram o mesmo blob e
    // conferem o mesmo plaintext — prova interoperabilidade determinística
    // sem precisar de dois dispositivos reais.
    const recipientPrivateKeyHex =
        'ebea44b99557c83965e6152a1393a5c6d74fe114f0a626f51bb2349e815136b2';
    const blobBase64 =
        'AqQAXxG3rw53DVihUXbTzqHcENoLZGbHFsnNHPFvZduk0FF00QwiZMLWLCs8q19CzAj4kYiWXr1jUTn0tUxh1ibNVbwPQiCSBZAJdH1eqE86qT1Na5ytsA==';
    const expectedPlaintext = 'truthid-vault-entry-fixture';

    test('decifra o blob fixo e bate com o plaintext esperado', () async {
      final privBytes = _hexToBytes(recipientPrivateKeyHex);
      final blob = base64Decode(blobBase64);

      final plaintext = await ecies.decrypt(blob, privBytes);

      expect(utf8.decode(plaintext), expectedPlaintext);
    });
  });
}

Future<String> _publicKeyHexFor(
  Uint8List privateKeyBytes, {
  bool compressed = true,
}) async {
  final priv = PrivateKey.fromBytes(getSecp256k1(), privateKeyBytes);
  final pub = priv.publicKey;
  return compressed ? pub.toCompressedHex() : pub.toHex();
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

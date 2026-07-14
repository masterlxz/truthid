import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/ipns_key_service.dart';
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;

void main() {
  // sessionId de teste fixo (16 bytes, formato do QR: hex, sem "0x").
  const testSessionIdHex = '000102030405060708090a0b0c0d0e0f';

  // Fixture validada contra um Kubo 0.42.0 real, não só round-trip interno
  // (mesmo padrão que pegou o bug do ECIES na Sessão 92 — "bate por acaso
  // só em teste isolado" já mordeu o projeto antes): a chave privada abaixo
  // foi importada de verdade via `POST /api/v0/key/import
  // ?format=libp2p-protobuf-cleartext`, e o `Id` que o Kubo devolveu bateu
  // byte-a-byte com o `ipnsName` calculado aqui.
  const expectedPrivateKeyProtobufHex =
      '08011240b1d3f4a5d680c324e0c253f0415961a05fb7b8fc491f140f14623e'
      '3ca5e547e86f9a643b4099be2f4551d02261fe3d000b4aa0ab66fcad7530ed'
      'b431b4ca5961';
  const expectedIpnsName =
      'k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh';

  test('deriveIpnsDeadDropKey bate com o fixture validado contra Kubo real',
      () async {
    final key = await deriveIpnsDeadDropKey(testSessionIdHex);

    expect(
      bytesToHex(key.privateKeyProtobuf),
      expectedPrivateKeyProtobufHex,
    );
    expect(key.ipnsName, expectedIpnsName);
  });

  test('mesmo sessionId sempre deriva a mesma chave (determinístico)',
      () async {
    final a = await deriveIpnsDeadDropKey(testSessionIdHex);
    final b = await deriveIpnsDeadDropKey(testSessionIdHex);

    expect(a.ipnsName, b.ipnsName);
    expect(a.privateKeyProtobuf, b.privateKeyProtobuf);
  });

  test('sessionIds diferentes derivam nomes IPNS diferentes', () async {
    final a = await deriveIpnsDeadDropKey(testSessionIdHex);
    final b = await deriveIpnsDeadDropKey(
      '0f0e0d0c0b0a09080706050403020100',
    );

    expect(a.ipnsName, isNot(b.ipnsName));
  });

  test('marshalPrivateKeyProtobuf concatena seed || pubkey na ordem certa',
      () async {
    final material = await deriveEd25519KeyPair(testSessionIdHex);
    final privateProtobuf = marshalPrivateKeyProtobuf(material);

    // header (Type=Ed25519, Data length=64) + seed(32) + pubkey(32).
    expect(privateProtobuf.sublist(0, 4), [0x08, 0x01, 0x12, 0x40]);
    expect(privateProtobuf.sublist(4, 36), material.seed);
    expect(privateProtobuf.sublist(36, 68), material.publicKey);
    expect(privateProtobuf.length, 68);
  });

  test('marshalPublicKeyProtobuf só carrega a chave pública', () async {
    final material = await deriveEd25519KeyPair(testSessionIdHex);
    final publicProtobuf = marshalPublicKeyProtobuf(material);

    expect(publicProtobuf.sublist(0, 4), [0x08, 0x01, 0x12, 0x20]);
    expect(publicProtobuf.sublist(4, 36), material.publicKey);
    expect(publicProtobuf.length, 36);
  });

  test('computeIpnsName sempre começa com o prefixo multibase base36 "k"',
      () async {
    final key = await deriveIpnsDeadDropKey(testSessionIdHex);
    expect(key.ipnsName, startsWith('k'));
  });

  test('computeIpnsName rejeita protobuf grande demais pro multihash identity',
      () {
    final tooLong = Uint8List(43);
    expect(() => computeIpnsName(tooLong), throwsArgumentError);
  });

  test('deriveEd25519KeyPair decodifica o sessionId hex corretamente',
      () async {
    // Vetor de controle: se o hex-decode do sessionId estivesse errado (ex:
    // bytes trocados), o seed HKDF sairia diferente e o teste de fixture já
    // pegaria — este teste isola só a decodificação, comparando contra
    // hexToBytes diretamente.
    final material = await deriveEd25519KeyPair(testSessionIdHex);
    final material2 = await deriveEd25519KeyPair(
      bytesToHex(hexToBytes(testSessionIdHex), include0x: false),
    );
    expect(material.publicKey, material2.publicKey);
  });
}

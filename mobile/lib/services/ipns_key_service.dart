import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';

/// Derivação determinística de uma chave IPNS a partir do `sessionId` do QR
/// de sessão da extensão de navegador — 13.9, fatia 2a (dead-drop
/// IPFS/IPNS). A extensão nunca recebe conexão de entrada e o QR já foi
/// mostrado antes do celular entrar em cena, então o nome IPNS onde o Mobile
/// vai publicar o blob cifrado precisa ser calculável pela extensão sozinha,
/// sem nenhuma troca extra — a única informação em comum é o `sessionId`
/// (16 bytes aleatórios, hex) já embutido no QR.
///
/// Matemática pura, sem I/O — quem publica de verdade é
/// `IpfsPinClient.publishDeadDrop`. Formato validado contra um Kubo real
/// (não só consistência interna) antes de virar fixture de teste, seguindo o
/// mesmo padrão que pegou o bug do ECIES na Sessão 92 (bater "por acaso" só
/// em teste isolado, nunca validado ponta-a-ponta).
const _ipnsHkdfSalt = 'TruthID Vault IPNS';
const _ipnsHkdfInfo = 'dead-drop-key-v1';

const int _keyTypeEd25519 = 1;
const int _multicodecLibp2pKey = 0x72;
const int _multihashIdentity = 0x00;
const String _base36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

class Ed25519KeyMaterial {
  final Uint8List seed;
  final Uint8List publicKey;

  const Ed25519KeyMaterial({required this.seed, required this.publicKey});
}

class IpnsDeadDropKey {
  final Uint8List privateKeyProtobuf;
  final String ipnsName;

  const IpnsDeadDropKey({
    required this.privateKeyProtobuf,
    required this.ipnsName,
  });
}

/// Deriva o par Ed25519 a partir do `sessionId` (hex). `seed` aqui é o seed
/// de 32 bytes que `package:cryptography` usa pra gerar a chave — não é o
/// mesmo `Data` de 64 bytes que o protobuf do libp2p espera pra chave
/// privada (isso é montado depois, em [marshalPrivateKeyProtobuf]).
Future<Ed25519KeyMaterial> deriveEd25519KeyPair(String sessionIdHex) async {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  final seed = hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_ipnsHkdfSalt),
    info: utf8.encode(_ipnsHkdfInfo),
    length: 32,
  );

  final keyPair = await crypt.Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();

  return Ed25519KeyMaterial(
    seed: seed,
    publicKey: Uint8List.fromList(publicKey.bytes),
  );
}

/// Protobuf `PrivateKey` do libp2p (`crypto.proto`): `Type` (varint,
/// Ed25519=1) + `Data` (bytes = seed(32) || pubkey(32), 64 bytes — é o
/// formato que `ed25519.PrivateKey` do Go usa, que é o que o Kubo espera em
/// `key/import` com `format=libp2p-protobuf-cleartext`).
Uint8List marshalPrivateKeyProtobuf(Ed25519KeyMaterial key) {
  final data = Uint8List.fromList([...key.seed, ...key.publicKey]);
  return _marshalKeyProtobuf(data);
}

/// Protobuf `PublicKey` do libp2p — `Data` = só os 32 bytes da chave pública.
Uint8List marshalPublicKeyProtobuf(Ed25519KeyMaterial key) {
  return _marshalKeyProtobuf(key.publicKey);
}

// Mensagem protobuf de 2 campos (`Type` varint, `Data` bytes) — igual pra
// PrivateKey e PublicKey no `crypto.proto` do libp2p. Não é um encoder
// protobuf genérico: só cobre o caso concreto usado aqui (Type=Ed25519,
// Data sempre < 128 bytes, então tag e length cabem num byte de varint cada).
Uint8List _marshalKeyProtobuf(Uint8List data) {
  if (data.length >= 128) {
    throw ArgumentError('data too long for single-byte varint length');
  }
  return Uint8List.fromList([
    0x08, _keyTypeEd25519, // field 1 (Type), varint
    0x12, data.length, // field 2 (Data), length-delimited
    ...data,
  ]);
}

/// Nome IPNS (`k51...`) a partir do protobuf da chave pública: multihash
/// "identity" (código 0x00, válido porque o protobuf de 36 bytes de uma
/// chave pública Ed25519 sempre cabe no limite de 42 bytes da regra de
/// peer-id do libp2p — https://github.com/libp2p/specs/blob/master/peer-ids/peer-ids.md)
/// → CIDv1 com codec `libp2p-key` (0x72) → multibase base36-lower (prefixo
/// `k`), formato que o Kubo usa hoje por padrão pra nomes IPNS.
String computeIpnsName(Uint8List publicKeyProtobuf) {
  if (publicKeyProtobuf.length > 42) {
    throw ArgumentError(
      'public key protobuf too long for identity multihash '
      '(${publicKeyProtobuf.length} > 42)',
    );
  }

  final multihash = Uint8List.fromList([
    _multihashIdentity,
    publicKeyProtobuf.length,
    ...publicKeyProtobuf,
  ]);

  final cid = Uint8List.fromList([
    0x01, // CID version 1
    _multicodecLibp2pKey,
    ...multihash,
  ]);

  return 'k${_base36Encode(cid)}';
}

// Codificação base36 "estilo base58" (mesma família de algoritmo do
// `base-x`/multibase): trata os bytes como um inteiro big-endian e converte
// pra base 36; bytes 0x00 à esquerda viram '0' à esquerda no resultado, em
// vez de serem absorvidos pelo valor numérico.
String _base36Encode(Uint8List bytes) {
  if (bytes.isEmpty) return '';

  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }

  const base = 36;
  final digits = <String>[];
  if (value == BigInt.zero) {
    digits.add('0');
  } else {
    while (value > BigInt.zero) {
      digits.add(_base36Alphabet[(value % BigInt.from(base)).toInt()]);
      value = value ~/ BigInt.from(base);
    }
  }

  final leadingZeroBytes = bytes.takeWhile((b) => b == 0).length;
  return ('0' * leadingZeroBytes) + digits.reversed.join();
}

/// Orquestra os passos acima: dado o `sessionId` do QR, devolve a chave
/// privada pronta pra `IpfsPinClient.publishDeadDrop` importar no Kubo, e o
/// nome IPNS que o resultado vai ter (o mesmo que a extensão recalcula do
/// lado dela, na fatia 2b, sem nunca ver a chave privada).
Future<IpnsDeadDropKey> deriveIpnsDeadDropKey(String sessionIdHex) async {
  final material = await deriveEd25519KeyPair(sessionIdHex);
  final privateKeyProtobuf = marshalPrivateKeyProtobuf(material);
  final publicKeyProtobuf = marshalPublicKeyProtobuf(material);
  return IpnsDeadDropKey(
    privateKeyProtobuf: privateKeyProtobuf,
    ipnsName: computeIpnsName(publicKeyProtobuf),
  );
}

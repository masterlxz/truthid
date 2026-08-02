import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';
import 'libp2p_key_util.dart' as libp2p;

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
  return libp2p.marshalKeyProtobuf(data);
}

/// Protobuf `PublicKey` do libp2p — `Data` = só os 32 bytes da chave pública.
Uint8List marshalPublicKeyProtobuf(Ed25519KeyMaterial key) {
  return libp2p.marshalKeyProtobuf(key.publicKey);
}

/// Nome IPNS (`k51...`) a partir do protobuf da chave pública — ver
/// `libp2p_key_util.dart::computeIpnsNameFromPublicKeyProtobuf` pro desenho
/// completo (multihash identity → CIDv1 libp2p-key → base36).
String computeIpnsName(Uint8List publicKeyProtobuf) =>
    libp2p.computeIpnsNameFromPublicKeyProtobuf(publicKeyProtobuf);

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

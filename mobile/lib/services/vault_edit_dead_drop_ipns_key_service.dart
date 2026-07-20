import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';

/// Deriva o nome IPNS onde a extensão publica o dead-drop cross-network do
/// vault-edit (item 6 do backlog, `PROJECT_STATE.md`) — mirror parcial de
/// `IpnsKeyService`, papel invertido: lá o Mobile publica e a extensão só
/// recomputa o nome público; aqui a **extensão** publica
/// (`extension/src/vaultEdit/deadDropIpnsKey.ts`) e o celular só precisa da
/// metade pública pra fazer `poll` — nunca vê nem precisa da chave privada.
///
/// `HKDF_SALT`/`HKDF_INFO` domain-separados dos usados por `IpnsKeyService`
/// (mesmo padrão do resto do projeto, ex: `VaultEditContentCipherService`
/// vs o cipher do `/pin`) — precisam bater byte-a-byte com
/// `extension/src/vaultEdit/deadDropIpnsKey.ts`.
const _hkdfSalt = 'TruthID Vault Edit IPNS';
const _hkdfInfo = 'dead-drop-key-v1';

const int _keyTypeEd25519 = 1;
const int _multicodecLibp2pKey = 0x72;
const int _multihashIdentity = 0x00;
const String _base36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

// Protobuf `PublicKey` do libp2p (`crypto.proto`): `Type` (varint,
// Ed25519=1) + `Data` (bytes = chave pública, 32 bytes) — mesma mensagem de
// 2 campos usada em `ipns_key_service.dart::_marshalKeyProtobuf`.
Uint8List _marshalPublicKeyProtobuf(Uint8List publicKey) {
  return Uint8List.fromList([0x08, _keyTypeEd25519, 0x12, publicKey.length, ...publicKey]);
}

// Codificação base36 "estilo base58" — mesma implementação de
// `ipns_key_service.dart::_base36Encode` (sem pacote maduro pra
// CID/multihash/multibase disponível pro Dart, hand-rolled com vetor de
// teste, como lá).
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

String _computeIpnsName(Uint8List publicKeyProtobuf) {
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

/// Recalcula o nome IPNS (`k51...`) onde a extensão publica o dead-drop pra
/// esse `sessionId` (hex, já embutido no QR de `truthid-vault-edit`) — a
/// única informação em comum entre os dois lados.
Future<String> computeIpnsNameForSession(String sessionIdHex) async {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  final seed = hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_hkdfSalt),
    info: utf8.encode(_hkdfInfo),
    length: 32,
  );

  final keyPair = await crypt.Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyProtobuf = _marshalPublicKeyProtobuf(Uint8List.fromList(publicKey.bytes));

  return _computeIpnsName(publicKeyProtobuf);
}

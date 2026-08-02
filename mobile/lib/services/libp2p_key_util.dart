import 'dart:typed_data';

/// Matemática compartilhada entre `ipns_key_service.dart` (pareamento de
/// leitura, Sessão 99) e `vault_edit_dead_drop_ipns_key_service.dart` (item 6
/// do backlog, Sessão 137) — achado #9 (cleanup) do `/code-review` da Sessão
/// 140: os dois arquivos duplicavam byte a byte a montagem do protobuf de
/// chave libp2p e a codificação CID/multihash/base36. Só a derivação HKDF
/// (salt/info, domain-separada por namespace) e a orquestração continuam
/// distintas em cada arquivo — extrair isso junto misturaria os dois
/// namespaces, que precisam ficar sempre separados.
///
/// Sem pacote maduro pra CID/multihash/multibase disponível pro Dart —
/// hand-rolled, validado contra um Kubo 0.42.0 real (Sessão 100) e contra o
/// mirror TypeScript (`extension/src/session/ipnsKey.ts`/`vaultEdit/
/// deadDropIpnsKey.ts`, que usa o pacote oficial `multiformats`).

const int keyTypeEd25519 = 1;
const int multicodecLibp2pKey = 0x72;
const int multihashIdentity = 0x00;
const String _base36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Mensagem protobuf de 2 campos (`Type` varint, `Data` bytes) do
/// `crypto.proto` do libp2p — mesmo formato pra PrivateKey (`Data` =
/// seed(32) || pubkey(32)) e PublicKey (`Data` = só a chave pública, 32
/// bytes). Não é um encoder protobuf genérico: só cobre o caso concreto
/// usado aqui (Type=Ed25519, Data sempre < 128 bytes, tag e length cabem
/// num byte de varint cada).
Uint8List marshalKeyProtobuf(Uint8List data) {
  if (data.length >= 128) {
    throw ArgumentError('data too long for single-byte varint length');
  }
  return Uint8List.fromList([
    0x08, keyTypeEd25519, // field 1 (Type), varint
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
String computeIpnsNameFromPublicKeyProtobuf(Uint8List publicKeyProtobuf) {
  if (publicKeyProtobuf.length > 42) {
    throw ArgumentError(
      'public key protobuf too long for identity multihash '
      '(${publicKeyProtobuf.length} > 42)',
    );
  }

  final multihash = Uint8List.fromList([
    multihashIdentity,
    publicKeyProtobuf.length,
    ...publicKeyProtobuf,
  ]);

  final cid = Uint8List.fromList([
    0x01, // CID version 1
    multicodecLibp2pKey,
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

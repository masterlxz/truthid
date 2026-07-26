import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf.dart';

/// Deterministic derivation of the IPNS name the mobile app publishes its
/// dead-drop response to, from the `sessionId` already embedded in the QR —
/// same algorithm as `mobile/lib/services/ipns_key_service.dart`. Pure math,
/// no I/O: the requester only ever needs the *public* half (to compute the
/// name to poll), never the private key (that's the mobile's job to publish
/// with).
const _ipnsHkdfSalt = 'TruthID Vault IPNS';
const _ipnsHkdfInfo = 'dead-drop-key-v1';

const int _keyTypeEd25519 = 1;
const int _multicodecLibp2pKey = 0x72;
const int _multihashIdentity = 0x00;
const String _base36Alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Derives the Ed25519 public key from the `sessionId` (hex) and returns the
/// IPNS name (`k51...`) the mobile will publish its response under.
Future<String> deriveDeadDropIpnsName(String sessionIdHex) async {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  final seed = hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_ipnsHkdfSalt),
    info: utf8.encode(_ipnsHkdfInfo),
    length: 32,
  );

  final keyPair = await crypt.Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyProtobuf = _marshalKeyProtobuf(Uint8List.fromList(publicKey.bytes));
  return _computeIpnsName(publicKeyProtobuf);
}

// Two-field protobuf message (`Type` varint, `Data` bytes) — same as the
// libp2p `crypto.proto` PublicKey message. Not a general protobuf encoder:
// only covers this concrete case (Type=Ed25519, Data always < 128 bytes, so
// tag and length each fit in a single varint byte).
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

// IPNS name (`k51...`) from the public key protobuf: "identity" multihash
// (code 0x00, valid because a 36-byte Ed25519 public key protobuf always
// fits the 42-byte libp2p peer-id limit) → CIDv1 with the `libp2p-key` codec
// (0x72) → base36-lower multibase (`k` prefix) — the format Kubo uses today
// by default for IPNS names.
String _computeIpnsName(Uint8List publicKeyProtobuf) {
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

// base36 encoding, "base58-style": treats the bytes as a big-endian integer
// and converts to base 36; leading 0x00 bytes become leading '0's in the
// result instead of being absorbed into the numeric value.
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

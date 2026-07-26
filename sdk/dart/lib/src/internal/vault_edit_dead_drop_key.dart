import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf.dart';
import 'ipns_key.dart' show marshalKeyProtobuf, computeIpnsName;

/// Deterministic derivation of the dead-drop IPNS *keypair* for a
/// `vault-edit` proposal (P27) — inverted role from `ipns_key.dart`: there,
/// the requester only ever recomputes the *public* name (the phone
/// publishes the response). Here, the requester itself has the proposal
/// content ready as soon as the QR exists, so it needs the full private key
/// to publish — mirror of `extension/src/vaultEdit/deadDropIpnsKey.ts`.
///
/// `HKDF_SALT`/`HKDF_INFO` are domain-separated from `ipns_key.dart`'s (same
/// pattern as `vault_edit_content_cipher.dart` vs `pin_content_cipher.dart`)
/// so the same `sessionId` never derives the same keypair/name for both
/// protocols. Must match `extension/src/vaultEdit/deadDropIpnsKey.ts` and
/// `mobile/lib/services/vault_edit_dead_drop_ipns_key_service.dart`
/// byte-for-byte.
const _hkdfSalt = 'TruthID Vault Edit IPNS';
const _hkdfInfo = 'dead-drop-key-v1';

class VaultEditDeadDropKey {
  /// libp2p `PrivateKey` protobuf, `libp2p-protobuf-cleartext` format —
  /// exactly what Kubo's `key/import` expects as the request body.
  final Uint8List privateKeyProtobuf;

  /// IPNS name (`k51...`) this key publishes to.
  final String ipnsName;

  const VaultEditDeadDropKey({required this.privateKeyProtobuf, required this.ipnsName});
}

/// Derives the full Ed25519 keypair from the `sessionId` (hex) embedded in
/// the QR, ready to hand to Kubo's `key/import`.
Future<VaultEditDeadDropKey> deriveVaultEditDeadDropKey(String sessionIdHex) async {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  final seed = hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_hkdfSalt),
    info: utf8.encode(_hkdfInfo),
    length: 32,
  );

  final keyPair = await crypt.Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyBytes = Uint8List.fromList(publicKey.bytes);

  // `Data` of the libp2p PrivateKey protobuf for Ed25519 is seed(32) ||
  // pubkey(32) — same format the Go `ed25519.PrivateKey` uses, which is what
  // Kubo expects.
  final privateKeyData = Uint8List(64)
    ..setRange(0, 32, seed)
    ..setRange(32, 64, publicKeyBytes);

  final publicKeyProtobuf = marshalKeyProtobuf(publicKeyBytes);

  return VaultEditDeadDropKey(
    privateKeyProtobuf: marshalKeyProtobuf(privateKeyData),
    ipnsName: computeIpnsName(publicKeyProtobuf),
  );
}

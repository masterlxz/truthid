import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

/// Recovers the Ethereum address that produced [signatureHex] over [message]
/// via `personal_sign` (the "\x19Ethereum Signed Message:\n" + length prefix) —
/// the same scheme the mobile app's `signChallenge`/`signPersonalMessageToUint8List`
/// uses, and what `recoverMessageAddress` (viem, TS SDK) / `Account.recover_message`
/// (Python SDK) / `Eth::Signature.personal_recover` (Ruby SDK) verify.
///
/// Throws if [signatureHex] is malformed — callers should catch and treat
/// that as "invalid signature format", matching the other 3 SDKs.
String recoverPersonalSignatureAddress(String message, String signatureHex) {
  final messageBytes = Uint8List.fromList(utf8.encode(message));
  final prefix = '\x19Ethereum Signed Message:\n${messageBytes.length}';
  final prefixedMessage = Uint8List.fromList([
    ...utf8.encode(prefix),
    ...messageBytes,
  ]);
  final digest = keccak256(prefixedMessage);

  final sigBytes = hexToBytes(signatureHex);
  if (sigBytes.length != 65) {
    throw const FormatException('Signature must be 65 bytes (r || s || v)');
  }
  final r = bytesToUnsignedInt(sigBytes.sublist(0, 32));
  final s = bytesToUnsignedInt(sigBytes.sublist(32, 64));
  var v = sigBytes[64];
  if (v < 27) v += 27; // some signers emit v in {0, 1} instead of {27, 28}

  final publicKey = ecRecover(digest, MsgSignature(r, s, v));
  final addressBytes = publicKeyToAddress(publicKey);
  return EthereumAddress(addressBytes).hexEip55;
}

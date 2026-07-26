import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// HKDF-SHA256 single block (RFC 5869, restricted to `length <= 32` — a
/// single `T(1)` block already covers that, no need for multi-block
/// expansion). Same primitive as `mobile/lib/services/hkdf_util.dart` — used
/// with domain-separated `salt`/`info` per context (dead-drop IPNS key vs.
/// `/pin` content key).
Uint8List hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  required int length,
}) {
  assert(length <= 32, 'length must be <= 32 for single-block HKDF');

  final prk = crypto.Hmac(crypto.sha256, salt).convert(ikm).bytes;
  final t1 = crypto.Hmac(crypto.sha256, prk).convert([...info, 0x01]).bytes;

  return Uint8List.fromList(t1.sublist(0, length));
}

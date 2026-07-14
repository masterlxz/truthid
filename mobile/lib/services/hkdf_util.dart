import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// HKDF-SHA256 de bloco único (RFC 5869, restrito a `length <= 32` — um bloco
/// `T(1)` já cobre isso, não precisa da expansão em múltiplos blocos).
/// Compartilhado entre [VaultKeyService] (derivação da vault key a partir da
/// assinatura da wallet) e `IpnsKeyService` (derivação da chave IPNS do
/// dead-drop a partir do `sessionId`, 13.9 fatia 2a) — mesma primitiva, chaves
/// de contexto diferentes via `info`.
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

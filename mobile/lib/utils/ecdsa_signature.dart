import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

/// Assinatura ECDSA de 65 bytes (r||s||v) já separada nos 3 componentes que
/// `IdentityRegistry.createIdentity`/`derive_vault_key_from_wallet` esperam
/// — mesma convenção `r/s/v(27/28)` que todo o resto do app (Ledger, Trezor,
/// WalletConnect) já produz, ver P24 em PENDING.md.
class ParsedSignature {
  final Uint8List r; // 32 bytes
  final Uint8List s; // 32 bytes
  final int v; // convenção 27/28

  const ParsedSignature({required this.r, required this.s, required this.v});
}

/// Faz o parse de uma assinatura hex de 65 bytes devolvida por
/// `personal_sign` via WalletConnect (P68, fatia 1). Algumas wallets
/// devolvem `v` já na convenção 27/28, outras cru (0/1) — normaliza pra
/// 27/28 sempre, mesma convenção que `sign_ledger_transaction`/
/// `sign_trezor_transaction` (Desktop) já usam.
ParsedSignature parseSignatureHex(String hex) {
  final bytes = hexToBytes(hex);
  if (bytes.length != 65) {
    throw FormatException(
        'expected a 65-byte signature (r+s+v), got ${bytes.length} bytes');
  }

  var v = bytes[64];
  if (v < 27) v += 27;

  return ParsedSignature(
    r: Uint8List.sublistView(bytes, 0, 32),
    s: Uint8List.sublistView(bytes, 32, 64),
    v: v,
  );
}

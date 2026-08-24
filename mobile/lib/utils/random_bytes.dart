import 'dart:math';
import 'dart:typed_data';

/// 32 bytes aleatórios via `Random.secure()` — mesmo padrão já usado inline
/// em `arweave_transaction.dart`/`arweave_isolate.dart` pro salt da
/// transação Arweave. Extraído pra cá porque o salt do commit-reveal de
/// pareamento de device (P68, fatia 2) é o 2º call site independente do
/// mesmo padrão exato. Não é material de chave (RSA/EC), então não precisa
/// de `pointycastle`/`FortunaRandom` — só um nonce/salt.
Uint8List randomBytes32() {
  return Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));
}

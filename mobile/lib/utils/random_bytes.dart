import 'dart:math';
import 'dart:typed_data';

/// 32 bytes aleatórios via `Random.secure()` — usado tanto pelo salt da
/// transação Arweave (`arweave_transaction.dart`/`arweave_isolate.dart`)
/// quanto pelo salt do commit-reveal de pareamento de device (P68, fatia 2).
/// Não é material de chave (RSA/EC), então não precisa de
/// `pointycastle`/`FortunaRandom` — só um nonce/salt.
///
/// `Random.secure()` instanciado 1x fora do loop, não 32x dentro do
/// `List.generate` — cada instância faz sua própria leitura de entropia do
/// SO na criação (achado real, P82 #7).
Uint8List randomBytes32() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
}

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/export.dart' as pc;

import 'arweave_b64url.dart';
import 'arweave_jwk.dart';
import 'arweave_transaction.dart';

// RSA-4096 em pointycastle é Dart puro, sem aceleração nativa — mais lento
// que a crate `rsa` do Rust em qualquer hardware. Geração de wallet
// (generateJwk) e assinatura PSS (signTransaction) SEMPRE rodam aqui, em
// isolate dedicado, nunca direto na isolate de UI — independente de
// qualquer medição de performance (o custo de isolar é baixo, o de travar
// um frame de UI não é). Nenhum objeto pointycastle (RSAPrivateKey/
// RSAPublicKey) atravessa a fronteira do isolate — só tipos primitivos/
// Uint8List/ArweaveJwk (classe simples de strings), reconstruídos dentro
// do isolate a partir dos campos do JWK.

Future<ArweaveJwk> generateJwkInIsolate() => Isolate.run(generateJwk);

// Assina `tx` in-place, mesma interface de signTransaction (mutação
// direta de tx.signature/tx.id) — só que a assinatura em si roda isolada.
// O salt aleatório de 32 bytes é gerado dentro do isolate (Random.secure()
// tem estado por isolate, não compartilhado com a isolate principal).
Future<void> signTransactionInIsolate(ArweaveTransaction tx, ArweaveJwk jwk) async {
  final sigData = signatureData(tx);
  final sigBytes = await Isolate.run(() => _signInIsolate(jwk, sigData));
  final idDigest = sha256.convert(sigBytes).bytes;

  tx.signature = b64UrlEncode(sigBytes);
  tx.id = b64UrlEncode(Uint8List.fromList(idDigest));
}

Uint8List _signInIsolate(ArweaveJwk jwk, Uint8List sigData) {
  final (privateKey, _) = jwkToKeyPair(jwk);
  final saltBytes = Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));

  final signer = pc.PSSSigner(pc.RSAEngine(), pc.SHA256Digest(), pc.SHA256Digest());
  signer.init(true, pc.ParametersWithSalt(pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey), saltBytes));
  return signer.generateSignature(sigData).bytes;
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/export.dart' as pc;

import 'arweave_b64url.dart';

// Wallet Arweave no formato JWK (RFC 7517), RSA-4096 — mesmo formato usado
// por arweave-js/ArConnect. Espelha wallet.rs do cliente Arweave standalone
// do Desktop (desktop/src-tauri/src/arweave/wallet.rs). Todos os campos são
// base64url sem padding.
class ArweaveJwk {
  const ArweaveJwk({
    required this.kty,
    required this.n,
    required this.e,
    required this.d,
    required this.p,
    required this.q,
    required this.dp,
    required this.dq,
    required this.qi,
  });

  factory ArweaveJwk.fromJson(Map<String, dynamic> json) => ArweaveJwk(
        kty: json['kty'] as String,
        n: json['n'] as String,
        e: json['e'] as String,
        d: json['d'] as String,
        p: json['p'] as String,
        q: json['q'] as String,
        dp: json['dp'] as String,
        dq: json['dq'] as String,
        qi: json['qi'] as String,
      );

  final String kty;
  final String n;
  final String e;
  final String d;
  final String p;
  final String q;
  final String dp;
  final String dq;
  final String qi;

  Map<String, dynamic> toJson() => {
        'kty': kty,
        'n': n,
        'e': e,
        'd': d,
        'p': p,
        'q': q,
        'dp': dp,
        'dq': dq,
        'qi': qi,
      };

  // toString redigido de propósito — a instância carrega o material privado
  // completo da chave (d/p/q/dp/dq/qi); nunca trocar por um toString "de
  // conveniência" que devolva os campos crus, mesmo por engano (mesma
  // preocupação do `impl Debug` manual em wallet.rs). Só o prefixo do
  // modulus público (n) aparece, suficiente pra identificar a wallet em
  // logs/testes sem arriscar a chave privada.
  @override
  String toString() =>
      'ArweaveJwk(kty: $kty, n: ${n.length > 12 ? '${n.substring(0, 12)}...' : n}, '
      'd: [redacted], p: [redacted], q: [redacted])';
}

Uint8List _bigIntToBytesBE(BigInt n) {
  if (n == BigInt.zero) return Uint8List.fromList([0]);
  var hex = n.toRadixString(16);
  if (hex.length % 2 != 0) hex = '0$hex';
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

BigInt _bytesToBigIntBE(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

BigInt _lcm(BigInt a, BigInt b) => (a * b) ~/ a.gcd(b);

// Reconstrói o par de chaves pointycastle a partir dos componentes do JWK.
// Só n/e/d/p/q são necessários pra reconstrução — pointycastle recalcula o
// resto internamente quando precisa — mas dp/dq/qi são mantidos no JWK por
// compatibilidade com o formato padrão (RFC 7517 / arweave-js), mesma nota
// do wallet.rs original.
(pc.RSAPrivateKey, pc.RSAPublicKey) jwkToKeyPair(ArweaveJwk jwk) {
  final n = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.n));
  final e = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.e));
  final d = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.d));
  final p = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.p));
  final q = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.q));

  return (pc.RSAPrivateKey(n, d, p, q), pc.RSAPublicKey(n, e));
}

// Validação de consistência matemática dos componentes — pointycastle não
// tem um `.validate()` pronto equivalente ao da crate `rsa` do Rust, então
// isso é checado manualmente: o módulo bate com p*q, e d é o inverso
// modular de e em relação a lcm(p-1, q-1) (definição de RSA válido).
void _validateKeyComponents(ArweaveJwk jwk) {
  final n = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.n));
  final e = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.e));
  final d = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.d));
  final p = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.p));
  final q = _bytesToBigIntBE(b64UrlDecodeStrict(jwk.q));

  if (p * q != n) {
    throw const FormatException('JWK inconsistente: n != p*q');
  }
  final lambda = _lcm(p - BigInt.one, q - BigInt.one);
  if ((d * e) % lambda != BigInt.one) {
    throw const FormatException(
        'JWK inconsistente: d*e não é congruente a 1 mod lcm(p-1,q-1)');
  }
}

ArweaveJwk parseJwk(String json) {
  final Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(json) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw FormatException('JWK inválido: ${e.message}');
  }
  final ArweaveJwk jwk;
  try {
    jwk = ArweaveJwk.fromJson(decoded);
  } on TypeError {
    throw const FormatException('JWK inválido: campo ausente ou com tipo errado');
  }
  if (jwk.kty != 'RSA') {
    throw FormatException('kty inesperado (esperado RSA): ${jwk.kty}');
  }
  // Validação de round-trip: reconstrói/valida a chave — pega JWKs
  // malformados ou com componentes inconsistentes antes de qualquer uso.
  _validateKeyComponents(jwk);
  return jwk;
}

// Endereço da wallet: SHA-256 do modulus n (bytes crus, não da string
// base64url), codificado em base64url sem padding — mesma derivação usada
// por arweave-js.
String walletAddress(ArweaveJwk jwk) {
  final nBytes = b64UrlDecodeStrict(jwk.n);
  final digest = sha256.convert(nBytes).bytes;
  return b64UrlEncode(Uint8List.fromList(digest));
}

// Gera uma wallet RSA-4096 nova. Lento (segundos, não-determinístico em
// tempo — geração de primos é probabilística) — chamar sempre a partir de
// um isolate dedicado (ver arweave_wallet_service.dart), nunca direto na
// isolate de UI. Mesma exigência que o `spawn_blocking` do Rust.
ArweaveJwk generateJwk() {
  final secureRandom = pc.FortunaRandom();
  final seedSource = Random.secure();
  final seeds = Uint8List.fromList(List.generate(32, (_) => seedSource.nextInt(256)));
  secureRandom.seed(pc.KeyParameter(seeds));

  final keyGen = pc.RSAKeyGenerator();
  keyGen.init(pc.ParametersWithRandom(
    pc.RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 64),
    secureRandom,
  ));
  final pair = keyGen.generateKeyPair();
  final priv = pair.privateKey as pc.RSAPrivateKey;
  final pub = pair.publicKey as pc.RSAPublicKey;

  // pointycastle não calcula os componentes CRT (dp/dq/qi) automaticamente
  // como a crate `rsa` do Rust faz — calculados manualmente aqui.
  final p = priv.p!;
  final q = priv.q!;
  final d = priv.privateExponent!;
  final dp = d % (p - BigInt.one);
  final dq = d % (q - BigInt.one);
  final qi = q.modInverse(p); // qinv = q^-1 mod p, sempre positivo por definição

  return ArweaveJwk(
    kty: 'RSA',
    n: b64UrlEncode(_bigIntToBytesBE(pub.n!)),
    e: b64UrlEncode(_bigIntToBytesBE(pub.publicExponent!)),
    d: b64UrlEncode(_bigIntToBytesBE(d)),
    p: b64UrlEncode(_bigIntToBytesBE(p)),
    q: b64UrlEncode(_bigIntToBytesBE(q)),
    dp: b64UrlEncode(_bigIntToBytesBE(dp)),
    dq: b64UrlEncode(_bigIntToBytesBE(dq)),
    qi: b64UrlEncode(_bigIntToBytesBE(qi)),
  );
}

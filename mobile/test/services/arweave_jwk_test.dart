import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_jwk.dart';

void main() {
  final testWalletJson = File('test/fixtures/arweave/test_wallet.json').readAsStringSync();

  group('arweave_jwk', () {
    test('faz parse da wallet de teste fixa', () {
      final jwk = parseJwk(testWalletJson);
      expect(jwk.kty, 'RSA');
    });

    test('endereço da wallet é determinístico e tem 43 chars', () {
      final jwk = parseJwk(testWalletJson);
      final addr1 = walletAddress(jwk);
      final addr2 = walletAddress(jwk);
      expect(addr1, addr2);
      // endereço Arweave = 32 bytes base64url sem padding = 43 chars
      expect(addr1.length, 43);
    });

    // Cross-checado contra arweave-js real (`arweave.wallets.jwkToAddress`,
    // scratchpad Node descartável) nesta sessão — gap que o Rust nunca tinha
    // fechado (só validava determinismo, não o valor contra uma referência
    // independente).
    test('endereço bate com arweave-js real (cross-checado)', () {
      final jwk = parseJwk(testWalletJson);
      expect(walletAddress(jwk), 'zwYLZnytErQAb0-taJUwVav55JiiE1kVgPBsn2pcnHQ');
    });

    test('parseJwk rejeita JSON malformado', () {
      expect(
        () => parseJwk('{not json'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('JWK inválido'),
        )),
      );
    });

    test('parseJwk rejeita kty errado', () {
      final decoded = jsonDecode(testWalletJson) as Map<String, dynamic>;
      decoded['kty'] = 'EC';
      expect(
        () => parseJwk(jsonEncode(decoded)),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('kty inesperado'),
        )),
      );
    });

    test('parseJwk rejeita componentes inconsistentes (n != p*q)', () {
      final decoded = jsonDecode(testWalletJson) as Map<String, dynamic>;
      // troca um char do meio de "n" — invalida n == p*q sem quebrar o
      // base64url em si.
      final n = decoded['n'] as String;
      final mid = n.length ~/ 2;
      final tampered = n.substring(0, mid) +
          (n[mid] == 'A' ? 'B' : 'A') +
          n.substring(mid + 1);
      decoded['n'] = tampered;
      expect(
        () => parseJwk(jsonEncode(decoded)),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('JWK inconsistente'),
        )),
      );
    });

    test('round-trip serialize/parse preserva os campos', () {
      final jwk = parseJwk(testWalletJson);
      final serialized = jsonEncode(jwk.toJson());
      final reparsed = parseJwk(serialized);
      expect(reparsed.n, jwk.n);
      expect(reparsed.d, jwk.d);
    });

    test('jwkToKeyPair reconstrói chaves consistentes', () {
      final jwk = parseJwk(testWalletJson);
      final (priv, pub) = jwkToKeyPair(jwk);
      expect(priv.n, pub.n);
    });

    test('toString não vaza material privado', () {
      final jwk = parseJwk(testWalletJson);
      final s = jwk.toString();
      expect(s.contains(jwk.d), isFalse);
      expect(s.contains(jwk.p), isFalse);
      expect(s.contains(jwk.q), isFalse);
      expect(s, contains('[redacted]'));
    });
  });
}

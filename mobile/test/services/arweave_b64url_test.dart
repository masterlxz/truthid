import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_b64url.dart';

void main() {
  group('arweave_b64url', () {
    test('encode/decode estrito faz round-trip', () {
      final input = Uint8List.fromList(utf8.encode('hello world'));
      final encoded = b64UrlEncode(input);
      expect(encoded.contains('='), isFalse);
      expect(b64UrlDecodeStrict(encoded), equals(input));
    });

    test('decode estrito rejeita bits residuais não-canônicos', () {
      // 44 chars, alfabeto base64url válido, mas o último símbolo carrega
      // bits residuais != 0 — mesmo anchor que o ArLocal devolve, que expôs
      // a necessidade do decoder permissivo (espelha o vetor de
      // transaction.rs::lenient_decode_accepts_non_canonical_trailing_bits).
      const nonCanonical = 'vq1pzfxj6ba96uc9cyn3qj4hdspa0tlj5s04tfyi1w5';
      expect(() => b64UrlDecodeStrict(nonCanonical), throwsFormatException);
    });

    test('decode permissivo aceita o mesmo vetor não-canônico', () {
      const nonCanonical = 'vq1pzfxj6ba96uc9cyn3qj4hdspa0tlj5s04tfyi1w5';
      final decoded = b64UrlDecodeLenient(nonCanonical);
      expect(decoded.length, 32);
      expect(
        decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'bead69cdfc63e9b6bdeae73d7329f7aa3e2176ca5ad2d963e6cd38b5fca2d70e',
      );
    });

    test('decode permissivo bate com o estrito pra entrada canônica', () {
      // TEST_ANCHOR de transaction.rs (44 'q's + 'o') — canônico, os dois
      // decoders devem concordar.
      const canonical =
          'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo';
      expect(b64UrlDecodeLenient(canonical), equals(b64UrlDecodeStrict(canonical)));
    });

    test('decode permissivo rejeita caractere fora do alfabeto', () {
      expect(() => b64UrlDecodeLenient('abc+def'), throwsFormatException);
    });
  });
}

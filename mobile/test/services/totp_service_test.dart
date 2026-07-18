import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/totp_service.dart';

// RFC 6238 Appendix B test vectors (SHA1), base32 of the ASCII seed
// "12345678901234567890" — https://www.rfc-editor.org/rfc/rfc6238#appendix-B.
// The RFC's table lists 8-digit truncated values; taking `% 1e6` of each
// gives the 6-digit codes used here (this project always uses 6 digits).
// Same vectors asserted in desktop/src/utils/__tests__/totp.test.ts — the two
// implementations must always produce identical codes.
const rfc6238Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const rfc6238Vectors = <int, String>{
  59: '287082',
  1111111109: '081804',
  1111111111: '050471',
  1234567890: '005924',
  2000000000: '279037',
  20000000000: '353130',
};

void main() {
  group('generateTotpCode', () {
    for (final entry in rfc6238Vectors.entries) {
      test('matches RFC 6238 vector at t=${entry.key}', () {
        expect(generateTotpCode(rfc6238Secret, entry.key), entry.value);
      });
    }
  });

  group('base32Decode', () {
    test('decodes the RFC 6238 seed back to its ASCII bytes', () {
      final bytes = base32Decode(rfc6238Secret);
      expect(utf8.decode(bytes), '12345678901234567890');
    });

    test('ignores lowercase and stray whitespace', () {
      final bytes = base32Decode(' gezdgnbv gy3tqojq ');
      expect(bytes.isNotEmpty, true);
    });
  });

  group('parseTotpSecret', () {
    test('accepts a raw base32 secret', () {
      expect(parseTotpSecret(rfc6238Secret.toLowerCase()), rfc6238Secret);
    });

    test('extracts the secret from an otpauth:// URI', () {
      final uri =
          'otpauth://totp/Example:alice@example.com?secret=$rfc6238Secret&issuer=Example';
      expect(parseTotpSecret(uri), rfc6238Secret);
    });

    test('throws on an otpauth:// URI missing the secret param', () {
      expect(
        () => parseTotpSecret(
            'otpauth://totp/Example:alice@example.com?issuer=Example'),
        throwsFormatException,
      );
    });

    test('throws on empty input', () {
      expect(() => parseTotpSecret('   '), throwsFormatException);
    });

    test('throws on invalid characters', () {
      expect(() => parseTotpSecret('not-a-valid-secret!!!'),
          throwsFormatException);
    });
  });

  group('secondsRemaining', () {
    test('counts down within a 30s window', () {
      expect(secondsRemaining(0), 30);
      expect(secondsRemaining(1), 29);
      expect(secondsRemaining(29), 1);
      expect(secondsRemaining(30), 30);
    });
  });
}

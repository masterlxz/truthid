import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/webauthn_service.dart';

// Fixed vector — cross-checked byte-for-byte against
// desktop/src/utils/__tests__/webauthn.test.ts. Any change to these
// constants or the expected hex output below must be mirrored there.
const fixedPrivateKeyHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const fixedRpId = 'vault.truthid.test';
final fixedCredentialId = Uint8List.fromList(
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
);
final fixedChallenge = Uint8List.fromList(List.filled(32, 9));
const fixedOrigin = 'https://vault.truthid.test';

void main() {
  group('fixed vector (cross-checked with the TS implementation)', () {
    test('derives the expected public key coordinates', () {
      final (x, y) = publicKeyXYFromPrivateKeyHex(fixedPrivateKeyHex);

      expect(
        toHex(x),
        '515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f',
      );
      expect(
        toHex(y),
        '4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354',
      );
    });

    test('builds the expected authenticatorData for a registration', () {
      final (x, y) = publicKeyXYFromPrivateKeyHex(fixedPrivateKeyHex);
      final cosePublicKey = encodeCoseP256PublicKey(x, y);
      final authData = buildAuthenticatorData(
        rpId: fixedRpId,
        signCount: 0,
        attestedCredential: AttestedCredential(
          credentialId: fixedCredentialId,
          coseP256PublicKey: cosePublicKey,
        ),
      );

      // rpIdHash(32) || flags(1)=0x45 || signCount(4)=0 || aaguid(16)=0 ||
      // credIdLen(2)=16 || credId(16) || COSE key.
      expect(authData[32], 0x45);
      expect(authData.sublist(33, 37), [0, 0, 0, 0]);
      expect(toHex(authData.sublist(37, 53)), '00' * 16);
      expect(authData.sublist(53, 55), [0, 16]);
      expect(toHex(authData.sublist(55, 71)), toHex(fixedCredentialId));
      expect(toHex(authData.sublist(71)), toHex(cosePublicKey));
    });

    test('signs the expected assertion (deterministic ECDSA, RFC 6979)', () {
      final assertion = signAssertion(
        privateKeyHex: fixedPrivateKeyHex,
        rpId: fixedRpId,
        signCount: 0,
        challenge: fixedChallenge,
        origin: fixedOrigin,
      );

      expect(assertion.newSignCount, 1);
      expect(
        assertion.clientDataJSON,
        jsonEncode({
          'type': 'webauthn.get',
          'challenge': base64UrlEncodeNoPad(fixedChallenge),
          'origin': fixedOrigin,
        }),
      );
      expect(
        toHex(assertion.signatureDer),
        '3045022100ccd3940608dc3a8c278322b9ec9facf9d9ad93d142f975ba7cf30c5ddaa50454022019f943e29741ee8cb0d4b142947d1cec20c403a50d2d3885c37461f0bce0763f',
      );
    });
  });

  group('createPasskey + signAssertion (self-contained round-trip)', () {
    test('produces a signature that increments the sign counter', () {
      final passkey = createPasskey(
        rpId: 'example.com',
        challenge: Uint8List.fromList(List.filled(32, 7)),
        origin: 'https://example.com',
      );
      expect(passkey.signCount, 0);

      final assertion = signAssertion(
        privateKeyHex: passkey.privateKeyHex,
        rpId: 'example.com',
        signCount: passkey.signCount,
        challenge: Uint8List.fromList(List.filled(32, 8)),
        origin: 'https://example.com',
      );
      expect(assertion.newSignCount, 1);
    });
  });
}

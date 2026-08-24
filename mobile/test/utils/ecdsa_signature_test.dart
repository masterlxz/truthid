import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';

import 'package:truthid_mobile/utils/ecdsa_signature.dart';

void main() {
  group('parseSignatureHex', () {
    test('separa r, s e v corretamente (v já em 27/28)', () {
      final r = '11' * 32;
      final s = '22' * 32;
      final sig = parseSignatureHex('0x$r${s}1c'); // v = 0x1c = 28

      expect(bytesToHex(sig.r), r);
      expect(bytesToHex(sig.s), s);
      expect(sig.v, 28);
    });

    test('normaliza v cru (0/1) pra convenção 27/28', () {
      final r = '11' * 32;
      final s = '22' * 32;

      final sigV0 = parseSignatureHex('0x$r${s}00');
      expect(sigV0.v, 27);

      final sigV1 = parseSignatureHex('0x$r${s}01');
      expect(sigV1.v, 28);
    });

    test('lança pra assinatura com tamanho errado', () {
      expect(() => parseSignatureHex('0x1234'), throwsFormatException);
    });
  });
}

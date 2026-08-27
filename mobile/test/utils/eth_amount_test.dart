import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/utils/eth_amount.dart';

void main() {
  group('parseEthToWei', () {
    test('valor inteiro simples', () {
      expect(parseEthToWei('1'), BigInt.from(10).pow(18));
    });

    test('fração comum (0.001 ETH)', () {
      expect(parseEthToWei('0.001'), BigInt.parse('1000000000000000'));
    });

    test('zero', () {
      expect(parseEthToWei('0'), BigInt.zero);
    });

    test('string vazia — trata como zero', () {
      expect(parseEthToWei(''), BigInt.zero);
    });

    test('18 casas decimais exatas (precisão máxima do wei)', () {
      expect(parseEthToWei('0.000000000000000001'), BigInt.one);
    });

    test('mais de 18 casas decimais — lança FormatException', () {
      expect(() => parseEthToWei('0.0000000000000000001'),
          throwsFormatException);
    });

    test('mais de um ponto decimal — lança FormatException', () {
      expect(() => parseEthToWei('0.0.1'), throwsFormatException);
    });

    test('parte inteira + fracionária juntas', () {
      expect(parseEthToWei('1.5'), BigInt.parse('1500000000000000000'));
    });

    test('fração com menos de 18 dígitos completa com zeros à direita', () {
      expect(parseEthToWei('0.1'), BigInt.parse('100000000000000000'));
    });
  });

  group('weiToDecimalString', () {
    test('inverso exato de parseEthToWei pra um valor inteiro', () {
      expect(weiToDecimalString(BigInt.from(10).pow(18)), '1');
    });

    test('inverso exato de parseEthToWei pra uma fração comum', () {
      expect(
          weiToDecimalString(BigInt.parse('1000000000000000')), '0.001');
    });

    test('zero', () {
      expect(weiToDecimalString(BigInt.zero), '0');
    });

    test('zeros à direita da fração são cortados', () {
      expect(
          weiToDecimalString(BigInt.parse('1500000000000000000')), '1.5');
    });

    test('round-trip com parseEthToWei', () {
      final wei = parseEthToWei('0.000000000000000001');
      expect(weiToDecimalString(wei), '0.000000000000000001');
    });
  });
}

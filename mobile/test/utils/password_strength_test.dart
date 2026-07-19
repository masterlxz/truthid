import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/utils/password_generator.dart';
import 'package:truthid_mobile/utils/password_strength.dart';

void main() {
  group('passwordStrength', () {
    test('string vazia retorna score 0 e bits 0', () {
      final result = passwordStrength('');
      expect(result.score, 0);
      expect(result.bits, 0);
      expect(result.label, '');
    });

    test('sequência óbvia (abcdefgh) fica Fraca — comprimento efetivo baixo',
        () {
      final result = passwordStrength('abcdefgh');
      expect(result.score, 0);
      expect(result.label, 'Fraca');
      expect(result.bits, closeTo(2 * (log(26) / ln2), 1e-9));
    });

    test('repetição óbvia (aaaa1111) fica Fraca — comprimento efetivo baixo',
        () {
      final result = passwordStrength('aaaa1111');
      expect(result.score, 0);
      expect(result.label, 'Fraca');
      expect(result.bits, closeTo(4 * (log(36) / ln2), 1e-9));
    });

    test('sequência descendente (cba, 987) também é detectada', () {
      expect(passwordStrength('cba').bits, closeTo(2 * (log(26) / ln2), 1e-9));
      expect(passwordStrength('cba987').score, lessThanOrEqualTo(1));
    });

    test('senha curta só minúsculas fica Fraca', () {
      expect(passwordStrength('abcxyz').score, 0);
    });

    test('mistura de categorias sem padrões óbvios fica Forte ou Muito forte',
        () {
      final result = passwordStrength('Tr0ub4dor&3');
      expect(result.score, greaterThanOrEqualTo(2));
      expect(['Forte', 'Muito forte'], contains(result.label));
    });

    test(
        'senha gerada de 16 chars com todas as categorias fica Forte ou '
        'Muito forte', () {
      for (var i = 0; i < 10; i++) {
        final pw = generatePassword(const PasswordGeneratorOptions(
          length: 16,
          uppercase: true,
          lowercase: true,
          numbers: true,
          symbols: true,
        ));
        final result = passwordStrength(pw);
        expect(result.score, greaterThanOrEqualTo(2));
      }
    });

    test('score nunca sai da faixa 0-3', () {
      for (final pw in [
        'a',
        'ab',
        'abc123',
        'aaaaaaaaaaaaaaaaaaaa',
        'Zz9!Zz9!Zz9!Zz9!',
      ]) {
        final result = passwordStrength(pw);
        expect(result.score, greaterThanOrEqualTo(0));
        expect(result.score, lessThanOrEqualTo(3));
      }
    });
  });
}

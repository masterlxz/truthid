import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/utils/password_generator.dart';

const _allCategories = PasswordGeneratorOptions(
  length: 16,
  uppercase: true,
  lowercase: true,
  numbers: true,
  symbols: true,
);

void main() {
  group('generatePassword', () {
    test('retorna uma string com o tamanho exato pedido', () {
      for (final length in [4, 8, 16, 32, 64]) {
        final pw = generatePassword(_allCategories.copyWith(length: length));
        expect(pw.length, length);
      }
    });

    test('só usa caracteres das categorias selecionadas', () {
      final pw = generatePassword(const PasswordGeneratorOptions(
        length: 20,
        uppercase: true,
        lowercase: false,
        numbers: true,
        symbols: false,
      ));
      expect(RegExp(r'^[A-Z0-9]+$').hasMatch(pw), isTrue);
    });

    test('inclui pelo menos 1 caractere de cada categoria selecionada', () {
      for (var i = 0; i < 50; i++) {
        final pw = generatePassword(const PasswordGeneratorOptions(
          length: 8,
          uppercase: true,
          lowercase: true,
          numbers: true,
          symbols: true,
        ));
        expect(RegExp(r'[A-Z]').hasMatch(pw), isTrue);
        expect(RegExp(r'[a-z]').hasMatch(pw), isTrue);
        expect(RegExp(r'[0-9]').hasMatch(pw), isTrue);
        expect(
          RegExp(r'[!@#$%^&*()\-_=+\[\]{};:,.<>?]').hasMatch(pw),
          isTrue,
        );
      }
    });

    test('nunca inclui uma categoria não selecionada', () {
      for (var i = 0; i < 20; i++) {
        final pw = generatePassword(const PasswordGeneratorOptions(
          length: 12,
          uppercase: false,
          lowercase: true,
          numbers: false,
          symbols: false,
        ));
        expect(RegExp(r'^[a-z]+$').hasMatch(pw), isTrue);
      }
    });

    test('lança quando nenhuma categoria está selecionada', () {
      expect(
        () => generatePassword(const PasswordGeneratorOptions(
          length: 8,
          uppercase: false,
          lowercase: false,
          numbers: false,
          symbols: false,
        )),
        throwsArgumentError,
      );
    });

    test('lança quando o tamanho é menor que o nº de categorias selecionadas',
        () {
      expect(
        () => generatePassword(_allCategories.copyWith(length: 3)),
        throwsArgumentError,
      );
    });

    test('aceita tamanho igual ao nº de categorias selecionadas', () {
      final pw = generatePassword(_allCategories.copyWith(length: 4));
      expect(pw.length, 4);
    });

    test('produz resultados diferentes entre chamadas (aleatoriedade real)',
        () {
      final results =
          {for (var i = 0; i < 20; i++) generatePassword(_allCategories)};
      expect(results.length, greaterThan(1));
    });
  });
}

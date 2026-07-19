import 'dart:math';

/// Gerador de senha customizável — parte do gap "gerenciador de senhas de
/// verdade" (item 6 do roadmap). Mirror funcional do TS
/// (desktop/src/utils/passwordGenerator.ts), sem paridade byte-a-byte — cada
/// lado só precisa gerar uma senha forte localmente, sem vetor cruzado.
class PasswordGeneratorOptions {
  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool numbers;
  final bool symbols;

  const PasswordGeneratorOptions({
    required this.length,
    required this.uppercase,
    required this.lowercase,
    required this.numbers,
    required this.symbols,
  });

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? uppercase,
    bool? lowercase,
    bool? numbers,
    bool? symbols,
  }) =>
      PasswordGeneratorOptions(
        length: length ?? this.length,
        uppercase: uppercase ?? this.uppercase,
        lowercase: lowercase ?? this.lowercase,
        numbers: numbers ?? this.numbers,
        symbols: symbols ?? this.symbols,
      );
}

const _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _lowercase = 'abcdefghijklmnopqrstuvwxyz';
const _numbers = '0123456789';
const _symbols = '!@#\$%^&*()-_=+[]{};:,.<>?';

List<String> _categories(PasswordGeneratorOptions options) {
  final cats = <String>[];
  if (options.uppercase) cats.add(_uppercase);
  if (options.lowercase) cats.add(_lowercase);
  if (options.numbers) cats.add(_numbers);
  if (options.symbols) cats.add(_symbols);
  return cats;
}

/// Gera uma senha garantindo pelo menos 1 caractere de cada categoria
/// selecionada (1 char de cada categoria primeiro, resto preenchido do
/// alfabeto combinado, depois embaralhado com Fisher-Yates) — mesmo
/// algoritmo do TS. `Random.secure().nextInt(max)` já é uniforme por
/// contrato do SDK Dart, diferente do lado TS (que precisa de rejection
/// sampling manual sobre `crypto.getRandomValues`).
String generatePassword(PasswordGeneratorOptions options) {
  final cats = _categories(options);
  if (cats.isEmpty) {
    throw ArgumentError('select at least one character category');
  }
  if (options.length < cats.length) {
    throw ArgumentError(
      'length must be at least ${cats.length} for the selected categories',
    );
  }

  final random = Random.secure();
  final chars = <String>[
    for (final cat in cats) cat[random.nextInt(cat.length)],
  ];
  final alphabet = cats.join();
  for (var i = chars.length; i < options.length; i++) {
    chars.add(alphabet[random.nextInt(alphabet.length)]);
  }

  for (var i = chars.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }

  return chars.join();
}

import 'dart:math';

/// Indicador de força de senha — heurística própria, sem dependência nova
/// (tipo zxcvbn). Mirror funcional de
/// desktop/src/utils/passwordStrength.ts, sem paridade byte-a-byte exigida
/// (mesma decisão do password_generator.dart). Ver comentário do TS pra
/// explicação completa do algoritmo (entropia estimada em bits, comprimento
/// efetivo que ignora sequências/repetições óbvias a partir do 3º
/// caractere do padrão).
class PasswordStrengthResult {
  final int score; // 0-3
  final String label;
  final double bits;

  const PasswordStrengthResult({
    required this.score,
    required this.label,
    required this.bits,
  });
}

int _alphabetSize(String password) {
  var size = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) size += 26;
  if (RegExp(r'[A-Z]').hasMatch(password)) size += 26;
  if (RegExp(r'[0-9]').hasMatch(password)) size += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) {
    size += 25; // mesmo tamanho do _symbols de password_generator.dart
  }
  return size;
}

int _effectiveLength(String password) {
  var length = 0;
  for (var i = 0; i < password.length; i++) {
    if (i >= 2) {
      final a = password.codeUnitAt(i - 2);
      final b = password.codeUnitAt(i - 1);
      final c = password.codeUnitAt(i);
      final isRepeat = a == b && b == c;
      final isAscending = b - a == 1 && c - b == 1;
      final isDescending = a - b == 1 && b - c == 1;
      if (isRepeat || isAscending || isDescending) continue;
    }
    length++;
  }
  return length;
}

PasswordStrengthResult passwordStrength(String password) {
  if (password.isEmpty) {
    return const PasswordStrengthResult(score: 0, label: '', bits: 0);
  }

  final size = _alphabetSize(password);
  final bits = size > 0
      ? _effectiveLength(password) * (log(size) / ln2)
      : 0.0;

  if (bits < 28) return PasswordStrengthResult(score: 0, label: 'Fraca', bits: bits);
  if (bits < 60) return PasswordStrengthResult(score: 1, label: 'Razoável', bits: bits);
  if (bits < 90) return PasswordStrengthResult(score: 2, label: 'Forte', bits: bits);
  return PasswordStrengthResult(score: 3, label: 'Muito forte', bits: bits);
}

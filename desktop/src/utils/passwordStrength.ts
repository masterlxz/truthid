/**
 * Indicador de força de senha — heurística própria, sem dependência nova
 * (tipo zxcvbn). Baseada em entropia estimada em bits, não em pontos
 * ad-hoc somados: comprimento efetivo (sequências óbvias — repetição de
 * 3+ chars iguais, ou 3+ em sequência ascendente/descendente — param de
 * contar a partir do 3º char do padrão) vezes log2 do tamanho do alfabeto
 * usado. Não detecta senhas de dicionário (ex: "password") — limitação
 * consciente, é o preço de não trazer uma lib de dicionário externa.
 *
 * Mirror funcional em mobile/lib/utils/password_strength.dart, sem
 * paridade byte-a-byte exigida (mesma decisão do passwordGenerator.ts).
 */

export type PasswordStrengthScore = 0 | 1 | 2 | 3;

export type PasswordStrengthResult = {
  score: PasswordStrengthScore;
  label: string;
  bits: number;
};

function alphabetSize(password: string): number {
  let size = 0;
  if (/[a-z]/.test(password)) size += 26;
  if (/[A-Z]/.test(password)) size += 26;
  if (/[0-9]/.test(password)) size += 10;
  if (/[^a-zA-Z0-9]/.test(password)) size += 25; // mesmo tamanho do SYMBOLS de passwordGenerator.ts
  return size;
}

// Conta só os caracteres que não fazem parte de um padrão óbvio (repetição
// ou sequência de 3+) a partir do 3º elemento do padrão em diante.
function effectiveLength(password: string): number {
  let length = 0;
  for (let i = 0; i < password.length; i++) {
    if (i >= 2) {
      const a = password.charCodeAt(i - 2);
      const b = password.charCodeAt(i - 1);
      const c = password.charCodeAt(i);
      const isRepeat = a === b && b === c;
      const isAscending = b - a === 1 && c - b === 1;
      const isDescending = a - b === 1 && b - c === 1;
      if (isRepeat || isAscending || isDescending) continue;
    }
    length++;
  }
  return length;
}

export function passwordStrength(password: string): PasswordStrengthResult {
  if (!password) return { score: 0, label: "", bits: 0 };

  const size = alphabetSize(password);
  const bits = size > 0 ? effectiveLength(password) * Math.log2(size) : 0;

  if (bits < 28) return { score: 0, label: "Fraca", bits };
  if (bits < 60) return { score: 1, label: "Razoável", bits };
  if (bits < 90) return { score: 2, label: "Forte", bits };
  return { score: 3, label: "Muito forte", bits };
}

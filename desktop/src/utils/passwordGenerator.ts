/**
 * Gerador de senha customizável — parte do gap "gerenciador de senhas de
 * verdade" (item 6 do roadmap). Lógica pura, sem UI, mesmo espírito de
 * totp.ts/webauthn.ts. Diferente dessas duas, não precisa de paridade
 * byte-a-byte com o Mobile (mobile/lib/utils/password_generator.dart) — cada
 * lado só precisa gerar uma senha forte localmente, sem vetor cruzado.
 */

export type PasswordGeneratorOptions = {
  length: number;
  uppercase: boolean;
  lowercase: boolean;
  numbers: boolean;
  symbols: boolean;
};

const UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LOWERCASE = "abcdefghijklmnopqrstuvwxyz";
const NUMBERS = "0123456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{};:,.<>?";

function categories(options: PasswordGeneratorOptions): string[] {
  const cats: string[] = [];
  if (options.uppercase) cats.push(UPPERCASE);
  if (options.lowercase) cats.push(LOWERCASE);
  if (options.numbers) cats.push(NUMBERS);
  if (options.symbols) cats.push(SYMBOLS);
  return cats;
}

// Índice aleatório em [0, max) sem bias de módulo. Diferente dos usos
// existentes de crypto.getRandomValues no projeto (webauthn.ts, etc — que só
// pegam bytes brutos de tamanho fixo), aqui o alfabeto tem tamanho
// arbitrário: descarta bytes que cairiam na faixa que introduziria bias
// (256 não é múltiplo da maioria dos tamanhos de alfabeto) e sorteia de novo.
function randomIndex(max: number): number {
  const limit = 256 - (256 % max);
  const bytes = new Uint8Array(1);
  let value: number;
  do {
    crypto.getRandomValues(bytes);
    value = bytes[0];
  } while (value >= limit);
  return value % max;
}

function randomChar(alphabet: string): string {
  return alphabet[randomIndex(alphabet.length)];
}

function shuffle(chars: string[]): string[] {
  // Fisher-Yates, mesma fonte de aleatoriedade cripto-segura de randomIndex —
  // sem isso os caracteres "garantidos" (1 por categoria) sempre cairiam nas
  // primeiras posições da senha.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomIndex(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars;
}

/**
 * Gera uma senha garantindo pelo menos 1 caractere de cada categoria
 * selecionada. Lança erro se nenhuma categoria estiver marcada ou se
 * `length` for menor que o número de categorias (não dá pra garantir 1 de
 * cada nesse caso).
 */
export function generatePassword(options: PasswordGeneratorOptions): string {
  const cats = categories(options);
  if (cats.length === 0) {
    throw new Error("select at least one character category");
  }
  if (options.length < cats.length) {
    throw new Error(
      `length must be at least ${cats.length} for the selected categories`,
    );
  }

  const alphabet = cats.join("");
  const chars = cats.map((cat) => randomChar(cat));
  for (let i = chars.length; i < options.length; i++) {
    chars.push(randomChar(alphabet));
  }

  return shuffle(chars).join("");
}

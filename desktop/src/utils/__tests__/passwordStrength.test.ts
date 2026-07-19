import { describe, expect, it } from "vitest";
import { passwordStrength } from "../passwordStrength";
import { generatePassword } from "../passwordGenerator";

describe("passwordStrength", () => {
  it("string vazia retorna score 0 e bits 0", () => {
    const result = passwordStrength("");
    expect(result.score).toBe(0);
    expect(result.bits).toBe(0);
    expect(result.label).toBe("");
  });

  it("sequência óbvia (abcdefgh) fica Fraca — comprimento efetivo baixo", () => {
    const result = passwordStrength("abcdefgh");
    expect(result.score).toBe(0);
    expect(result.label).toBe("Fraca");
    // Só 'a' e 'b' contam — o resto é sequência ascendente ignorada.
    expect(result.bits).toBeCloseTo(2 * Math.log2(26), 5);
  });

  it("repetição óbvia (aaaa1111) fica Fraca — comprimento efetivo baixo", () => {
    const result = passwordStrength("aaaa1111");
    expect(result.score).toBe(0);
    expect(result.label).toBe("Fraca");
    expect(result.bits).toBeCloseTo(4 * Math.log2(36), 5);
  });

  it("sequência descendente (cba, 987) também é detectada", () => {
    // 'c','b' contam, 'a' fecha a sequência descendente e é ignorado.
    expect(passwordStrength("cba").bits).toBeCloseTo(2 * Math.log2(26), 5);
    // Mesma lógica pro trecho de dígitos '987' dentro de "cba987".
    expect(passwordStrength("cba987").score).toBeLessThanOrEqual(1);
  });

  it("senha curta só minúsculas fica Fraca", () => {
    expect(passwordStrength("abcxyz").score).toBe(0);
  });

  it("mistura de categorias sem padrões óbvios fica Forte ou Muito forte", () => {
    const result = passwordStrength("Tr0ub4dor&3");
    expect(result.score).toBeGreaterThanOrEqual(2);
    expect(["Forte", "Muito forte"]).toContain(result.label);
  });

  it("senha gerada de 16 chars com todas as categorias fica Forte ou Muito forte",
    () => {
      for (let i = 0; i < 10; i++) {
        const pw = generatePassword({
          length: 16,
          uppercase: true,
          lowercase: true,
          numbers: true,
          symbols: true,
        });
        const result = passwordStrength(pw);
        expect(result.score).toBeGreaterThanOrEqual(2);
      }
    });

  it("score nunca sai da faixa 0-3", () => {
    for (const pw of ["a", "ab", "abc123", "aaaaaaaaaaaaaaaaaaaa", "Zz9!Zz9!Zz9!Zz9!"]) {
      const result = passwordStrength(pw);
      expect(result.score).toBeGreaterThanOrEqual(0);
      expect(result.score).toBeLessThanOrEqual(3);
    }
  });
});

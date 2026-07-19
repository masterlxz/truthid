import { describe, expect, it } from "vitest";
import { generatePassword, type PasswordGeneratorOptions } from "../passwordGenerator";

const allCategories: PasswordGeneratorOptions = {
  length: 16,
  uppercase: true,
  lowercase: true,
  numbers: true,
  symbols: true,
};

describe("generatePassword", () => {
  it("returns a string with the exact requested length", () => {
    for (const length of [4, 8, 16, 32, 64]) {
      const pw = generatePassword({ ...allCategories, length });
      expect(pw.length).toBe(length);
    }
  });

  it("only uses characters from selected categories", () => {
    const pw = generatePassword({
      length: 20,
      uppercase: true,
      lowercase: false,
      numbers: true,
      symbols: false,
    });
    expect(pw).toMatch(/^[A-Z0-9]+$/);
  });

  it("includes at least one character from every selected category", () => {
    // Roda várias vezes — a garantia é determinística no algoritmo (1 char
    // de cada categoria antes do preenchimento aleatório), mas várias
    // rodadas blindam contra qualquer regressão que a torne só provável.
    for (let i = 0; i < 50; i++) {
      const pw = generatePassword({
        length: 8,
        uppercase: true,
        lowercase: true,
        numbers: true,
        symbols: true,
      });
      expect(pw).toMatch(/[A-Z]/);
      expect(pw).toMatch(/[a-z]/);
      expect(pw).toMatch(/[0-9]/);
      expect(pw).toMatch(/[!@#$%^&*()\-_=+[\]{};:,.<>?]/);
    }
  });

  it("never includes a category that was not selected", () => {
    for (let i = 0; i < 20; i++) {
      const pw = generatePassword({
        length: 12,
        uppercase: false,
        lowercase: true,
        numbers: false,
        symbols: false,
      });
      expect(pw).toMatch(/^[a-z]+$/);
    }
  });

  it("throws when no category is selected", () => {
    expect(() =>
      generatePassword({
        length: 8,
        uppercase: false,
        lowercase: false,
        numbers: false,
        symbols: false,
      }),
    ).toThrow();
  });

  it("throws when length is shorter than the number of selected categories", () => {
    expect(() => generatePassword({ ...allCategories, length: 3 })).toThrow();
  });

  it("allows length equal to the number of selected categories", () => {
    const pw = generatePassword({ ...allCategories, length: 4 });
    expect(pw.length).toBe(4);
  });

  it("produces different results across calls (real randomness, no fixed seed)", () => {
    const results = new Set(
      Array.from({ length: 20 }, () => generatePassword(allCategories)),
    );
    expect(results.size).toBeGreaterThan(1);
  });
});

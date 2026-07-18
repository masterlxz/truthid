import { describe, expect, it } from "vitest";
import {
  base32Decode,
  generateTotpCode,
  parseTotpSecret,
  secondsRemaining,
} from "../totp";

// RFC 6238 Appendix B test vectors (SHA1), base32 of the ASCII seed
// "12345678901234567890" — https://www.rfc-editor.org/rfc/rfc6238#appendix-B.
// The RFC's table lists 8-digit truncated values; taking `% 1e6` of each
// gives the 6-digit codes used here (this project always uses 6 digits).
const RFC_6238_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const RFC_6238_VECTORS: Array<[number, string]> = [
  [59, "287082"],
  [1111111109, "081804"],
  [1111111111, "050471"],
  [1234567890, "005924"],
  [2000000000, "279037"],
  [20000000000, "353130"],
];

describe("generateTotpCode", () => {
  it.each(RFC_6238_VECTORS)(
    "matches RFC 6238 vector at t=%i",
    async (t, expected) => {
      const code = await generateTotpCode(RFC_6238_SECRET, t);
      expect(code).toBe(expected);
    },
  );
});

describe("base32Decode", () => {
  it("decodes the RFC 6238 seed back to its ASCII bytes", () => {
    const bytes = base32Decode(RFC_6238_SECRET);
    expect(new TextDecoder().decode(bytes)).toBe("12345678901234567890");
  });

  it("ignores lowercase and stray whitespace", () => {
    const bytes = base32Decode(" gezdgnbv gy3tqojq ");
    expect(bytes.length).toBeGreaterThan(0);
  });
});

describe("parseTotpSecret", () => {
  it("accepts a raw base32 secret", () => {
    expect(parseTotpSecret(RFC_6238_SECRET.toLowerCase())).toBe(
      RFC_6238_SECRET,
    );
  });

  it("extracts the secret from an otpauth:// URI", () => {
    const uri = `otpauth://totp/Example:alice@example.com?secret=${RFC_6238_SECRET}&issuer=Example`;
    expect(parseTotpSecret(uri)).toBe(RFC_6238_SECRET);
  });

  it("throws on an otpauth:// URI missing the secret param", () => {
    expect(() =>
      parseTotpSecret("otpauth://totp/Example:alice@example.com?issuer=Example"),
    ).toThrow();
  });

  it("throws on empty input", () => {
    expect(() => parseTotpSecret("   ")).toThrow();
  });

  it("throws on invalid characters", () => {
    expect(() => parseTotpSecret("not-a-valid-secret!!!")).toThrow();
  });
});

describe("secondsRemaining", () => {
  it("counts down within a 30s window", () => {
    expect(secondsRemaining(0)).toBe(30);
    expect(secondsRemaining(1)).toBe(29);
    expect(secondsRemaining(29)).toBe(1);
    expect(secondsRemaining(30)).toBe(30);
  });
});

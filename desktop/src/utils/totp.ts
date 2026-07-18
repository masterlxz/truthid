const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const STEP_SECONDS = 30;
const DIGITS = 6;

/**
 * Decodes a base32 (RFC 4648, no padding required) string into raw bytes.
 * TOTP secrets are conventionally base32-encoded (the format authenticator
 * apps show/scan), not base64.
 */
export function base32Decode(input: string): Uint8Array {
  const cleaned = input.toUpperCase().replace(/[^A-Z2-7]/g, "");
  const bytes: number[] = [];
  let bits = 0;
  let value = 0;

  for (const char of cleaned) {
    const idx = BASE32_ALPHABET.indexOf(char);
    if (idx === -1) throw new Error(`Invalid base32 character: ${char}`);
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((value >>> bits) & 0xff);
    }
  }

  return new Uint8Array(bytes);
}

/**
 * Accepts either a raw base32 TOTP secret or a full `otpauth://totp/...` URI
 * (what most sites encode into the 2FA setup QR code) and returns the clean
 * base32 secret. Throws if neither form yields a usable secret.
 */
export function parseTotpSecret(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) throw new Error("TOTP secret is empty");

  if (trimmed.toLowerCase().startsWith("otpauth://")) {
    const url = new URL(trimmed);
    const secret = url.searchParams.get("secret");
    if (!secret) throw new Error("otpauth:// URI has no secret parameter");
    return secret.toUpperCase();
  }

  const cleaned = trimmed.toUpperCase().replace(/\s+/g, "");
  if (!/^[A-Z2-7]+=*$/.test(cleaned)) {
    throw new Error("Not a valid base32 TOTP secret");
  }
  return cleaned;
}

/** Seconds left in the current 30s TOTP window for the given unix timestamp. */
export function secondsRemaining(unixSeconds: number): number {
  return STEP_SECONDS - (unixSeconds % STEP_SECONDS);
}

/**
 * Generates the current TOTP code (RFC 6238) for a base32 secret at a given
 * unix timestamp. Uses Web Crypto's HMAC-SHA1 (available in the Tauri
 * webview and in the jsdom test environment) rather than a hand-rolled
 * HMAC/SHA-1 implementation.
 */
export async function generateTotpCode(
  secretBase32: string,
  unixSeconds: number,
): Promise<string> {
  const keyBytes = base32Decode(secretBase32);
  const counter = Math.floor(unixSeconds / STEP_SECONDS);

  const counterBytes = new ArrayBuffer(8);
  const counterView = new DataView(counterBytes);
  // JS numbers are safe integers well past any realistic unix-time/30 value,
  // so the high 32 bits are always 0 here.
  counterView.setUint32(0, 0);
  counterView.setUint32(4, counter);

  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, counterBytes),
  );

  const offset = signature[signature.length - 1] & 0x0f;
  const binary =
    ((signature[offset] & 0x7f) << 24) |
    ((signature[offset + 1] & 0xff) << 16) |
    ((signature[offset + 2] & 0xff) << 8) |
    (signature[offset + 3] & 0xff);

  const code = (binary % 10 ** DIGITS).toString().padStart(DIGITS, "0");
  return code;
}

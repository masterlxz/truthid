/**
 * Hex <-> bytes compartilhado — antes duplicado em `crypto/ecies.ts` e
 * `entrypoints/popup/main.ts`; extraído aqui pra não virar uma terceira
 * cópia no `entrypoints/background.ts` (13.9, fatia 2b).
 */
export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

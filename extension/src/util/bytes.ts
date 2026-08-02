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

// Usado por `background.ts` (Fase 15.4, fatia 2) pra reempacotar o blob cru
// que `tryFetchDeadDrop` devolve no mesmo formato base64 que o caminho LAN
// já entrega pro `handleBlob` dos overlays (`addressOverlay.ts`/
// `creditCardOverlay.ts`), que fazem `atob()` sem se importar de onde o
// blob veio.
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function base64ToBytes(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

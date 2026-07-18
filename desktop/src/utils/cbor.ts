/**
 * Minimal deterministic CBOR (RFC 8949) encoder — only the subset needed to
 * build a COSE_Key map and a WebAuthn attestationObject map, both small,
 * fixed-shape, definite-length structures. No decoder, no bignums, no
 * floats, no indefinite-length items, no tags — anything beyond that is out
 * of scope on purpose.
 */

const MAJOR_UNSIGNED = 0;
const MAJOR_NEGATIVE = 1;
const MAJOR_BYTES = 2;
const MAJOR_TEXT = 3;
const MAJOR_MAP = 5;

function encodeHead(major: number, length: number): number[] {
  const highBits = major << 5;
  if (length < 24) {
    return [highBits | length];
  }
  if (length < 256) {
    return [highBits | 24, length];
  }
  if (length < 65536) {
    return [highBits | 25, (length >>> 8) & 0xff, length & 0xff];
  }
  throw new Error(`CBOR length too large for this minimal encoder: ${length}`);
}

/** Encodes a CBOR unsigned or negative integer (major type 0 or 1). */
export function encodeInt(value: number): Uint8Array {
  if (Number.isInteger(value) && value >= 0) {
    return new Uint8Array(encodeHead(MAJOR_UNSIGNED, value));
  }
  // CBOR negative integers encode `-1 - value` as the argument.
  return new Uint8Array(encodeHead(MAJOR_NEGATIVE, -1 - value));
}

/** Encodes a CBOR byte string (major type 2). */
export function encodeBytes(bytes: Uint8Array): Uint8Array {
  const head = encodeHead(MAJOR_BYTES, bytes.length);
  const out = new Uint8Array(head.length + bytes.length);
  out.set(head, 0);
  out.set(bytes, head.length);
  return out;
}

/** Encodes a CBOR text string (major type 3), UTF-8. */
export function encodeText(text: string): Uint8Array {
  const bytes = new TextEncoder().encode(text);
  const head = encodeHead(MAJOR_TEXT, bytes.length);
  const out = new Uint8Array(head.length + bytes.length);
  out.set(head, 0);
  out.set(bytes, head.length);
  return out;
}

function concat(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, c) => sum + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

/**
 * Encodes a CBOR definite-length map (major type 5) from an ordered list of
 * already-encoded key/value byte pairs. Order is caller-controlled and
 * preserved as-is (CBOR canonical key ordering is not enforced here — callers
 * must pass keys in the order the spec/consumer expects).
 */
export function encodeMap(entries: Array<[Uint8Array, Uint8Array]>): Uint8Array {
  const head = encodeHead(MAJOR_MAP, entries.length);
  const chunks = [new Uint8Array(head)];
  for (const [key, value] of entries) {
    chunks.push(key, value);
  }
  return concat(chunks);
}

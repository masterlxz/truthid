import 'dart:convert';
import 'dart:typed_data';

/// Minimal deterministic CBOR (RFC 8949) encoder — espelho funcional de
/// `desktop/src/utils/cbor.ts`. Só o subconjunto necessário pra montar um mapa
/// COSE_Key e um mapa attestationObject do WebAuthn, ambos pequenos, de forma
/// fixa e comprimento definido. Sem decoder, sem bignums, sem floats, sem
/// itens de comprimento indefinido, sem tags.

const int _majorUnsigned = 0;
const int _majorNegative = 1;
const int _majorBytes = 2;
const int _majorText = 3;
const int _majorMap = 5;

List<int> _encodeHead(int major, int length) {
  final highBits = major << 5;
  if (length < 24) {
    return [highBits | length];
  }
  if (length < 256) {
    return [highBits | 24, length];
  }
  if (length < 65536) {
    return [highBits | 25, (length >> 8) & 0xff, length & 0xff];
  }
  throw ArgumentError('CBOR length too large for this minimal encoder: $length');
}

/// Encodes a CBOR unsigned or negative integer (major type 0 or 1).
Uint8List encodeInt(int value) {
  if (value >= 0) {
    return Uint8List.fromList(_encodeHead(_majorUnsigned, value));
  }
  // CBOR negative integers encode `-1 - value` as the argument.
  return Uint8List.fromList(_encodeHead(_majorNegative, -1 - value));
}

/// Encodes a CBOR byte string (major type 2).
Uint8List encodeBytes(List<int> bytes) {
  final head = _encodeHead(_majorBytes, bytes.length);
  return Uint8List.fromList([...head, ...bytes]);
}

/// Encodes a CBOR text string (major type 3), UTF-8.
Uint8List encodeText(String text) {
  final bytes = utf8.encode(text);
  final head = _encodeHead(_majorText, bytes.length);
  return Uint8List.fromList([...head, ...bytes]);
}

/// Encodes a CBOR definite-length map (major type 5) from an ordered list of
/// already-encoded key/value byte pairs. Order is caller-controlled and
/// preserved as-is.
Uint8List encodeMap(List<(Uint8List, Uint8List)> entries) {
  final head = _encodeHead(_majorMap, entries.length);
  final out = <int>[...head];
  for (final (key, value) in entries) {
    out.addAll(key);
    out.addAll(value);
  }
  return Uint8List.fromList(out);
}

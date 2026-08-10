import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha384;

// Deep hash do Arweave (ANS-104/formato-2, `ArweaveTeam/arweave-standards`)
// — SHA-384, 48 bytes de saída. Espelha deep_hash.rs do cliente Arweave
// standalone do Desktop (desktop/src-tauri/src/arweave/deep_hash.rs). NÃO
// confundir com o SHA-256 do merkle `data_root` (arweave_merkle.dart) — são
// dois algoritmos de hash diferentes dentro do mesmo fluxo de assinatura da
// transação.
sealed class DeepHashChunk {
  const DeepHashChunk();

  factory DeepHashChunk.blob(Uint8List bytes) = _DeepHashBlob;
  factory DeepHashChunk.utf8(String s) = _DeepHashUtf8;
  factory DeepHashChunk.list(List<DeepHashChunk> items) = _DeepHashList;
}

class _DeepHashBlob extends DeepHashChunk {
  const _DeepHashBlob(this.bytes);
  final Uint8List bytes;
}

class _DeepHashUtf8 extends DeepHashChunk {
  const _DeepHashUtf8(this.text);
  final String text;
}

class _DeepHashList extends DeepHashChunk {
  const _DeepHashList(this.items);
  final List<DeepHashChunk> items;
}

Uint8List _sha384(List<int> data) => Uint8List.fromList(sha384.convert(data).bytes);

Uint8List _concat(List<int> a, List<int> b) => Uint8List.fromList([...a, ...b]);

Uint8List deepHash(DeepHashChunk chunk) {
  switch (chunk) {
    case _DeepHashBlob(:final bytes):
      return _deepHashBlobBytes(bytes);
    case _DeepHashUtf8(:final text):
      return _deepHashBlobBytes(Uint8List.fromList(utf8.encode(text)));
    case _DeepHashList(:final items):
      final tag = _concat(utf8.encode('list'), utf8.encode(items.length.toString()));
      var acc = _sha384(tag);
      for (final item in items) {
        final itemHash = deepHash(item);
        acc = _sha384(_concat(acc, itemHash));
      }
      return acc;
  }
}

Uint8List _deepHashBlobBytes(Uint8List data) {
  final tag = _concat(utf8.encode('blob'), utf8.encode(data.length.toString()));
  final tagged = _concat(_sha384(tag), _sha384(data));
  return _sha384(tagged);
}

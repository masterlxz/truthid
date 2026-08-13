import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

// Merkle tree própria do Arweave (não Merkle-Patricia) sobre chunks do
// conteúdo, usada só pra derivar `data_root`/`data_path` — espelha
// `apps/arweave/src/ar_merkle.erl` / `arweave-js` `lib/merkle.ts`, e o
// porte Rust já validado em desktop/src-tauri/src/arweave/merkle.rs. Hash
// aqui é SHA-256 (32 bytes) — distinto do SHA-384 do deep hash
// (arweave_deep_hash.dart), que assina a tx em si, não o conteúdo.
//
// maxChunkSize/minChunkSize são constantes de PROTOCOLO do Arweave (mesmos
// valores de arweave-js lib/merkle.ts), não escolhas deste código — não dá
// pra extrair numa constante compartilhada de verdade entre Dart e Rust
// (sem pipeline de codegen cross-linguagem no projeto), então o par tem que
// ser mantido manualmente em sincronia com
// desktop/src-tauri/src/arweave/merkle.rs (MAX_CHUNK_SIZE/MIN_CHUNK_SIZE)
// — se um dia o protocolo mudar esses valores, atualize os dois junto,
// nunca só um (achado do /code-review, Sessão 195).
const int maxChunkSize = 256 * 1024;
const int minChunkSize = 32 * 1024;
const int _noteSize = 32;

class Chunk {
  const Chunk(this.dataHash, this.minByteRange, this.maxByteRange);
  final Uint8List dataHash;
  final int minByteRange;
  final int maxByteRange;
}

class Proof {
  const Proof(this.offset, this.proof);
  final int offset;
  final Uint8List proof;
}

// Árvore completa (não só a raiz) — necessária pra derivar a prova de
// inclusão (data_path) de cada folha via generateProofs, não só o
// data_root. Privada ao arquivo, mesmo padrão module-private do Rust — só
// a API pública (chunkData/computeDataRoot/generateProofs/
// chunkDataForUpload/validatePath) é exercitada por fora.
sealed class _NodeKind {}

class _Leaf extends _NodeKind {
  _Leaf(this.dataHash);
  final Uint8List dataHash;
}

class _Branch extends _NodeKind {
  _Branch(this.left, this.right);
  final _MerkleNode left;
  final _MerkleNode right;
}

class _MerkleNode {
  _MerkleNode(this.id, this.maxByteRange, this.kind);
  final Uint8List id;
  final int maxByteRange;
  final _NodeKind kind;
}

Uint8List _sha256(List<int> data) => Uint8List.fromList(sha256.convert(data).bytes);

Uint8List _sha256Concat(List<List<int>> parts) {
  final combined = <int>[];
  for (final p in parts) {
    combined.addAll(p);
  }
  return _sha256(combined);
}

// Representação big-endian de 32 bytes de um offset — mesmo `intToBuffer`
// de `arweave-js` (NOTE_SIZE = 32, não uma string decimal).
Uint8List _intToBuffer(int note) {
  final buffer = Uint8List(_noteSize);
  var n = note;
  for (var i = _noteSize - 1; i >= 0; i--) {
    buffer[i] = n % 256;
    n = n ~/ 256;
  }
  return buffer;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Divide `data` em chunks de até maxChunkSize. Se o último chunk ficaria
// menor que minChunkSize, rebalanceia dividindo o penúltimo chunk ao meio
// — mesma lógica de `chunkData` em arweave-js. `data` vazio produz um único
// chunk vazio (min=max=0), igual ao comportamento de referência.
List<Chunk> chunkData(Uint8List data) {
  final chunks = <Chunk>[];
  var rest = data;
  var cursor = 0;

  while (rest.length >= maxChunkSize) {
    var chunkSize = maxChunkSize;
    final nextChunkSize = rest.length - maxChunkSize;
    if (nextChunkSize > 0 && nextChunkSize < minChunkSize) {
      chunkSize = (rest.length + 1) ~/ 2;
    }
    final chunk = Uint8List.sublistView(rest, 0, chunkSize);
    final remainder = Uint8List.sublistView(rest, chunkSize);
    cursor += chunk.length;
    chunks.add(Chunk(_sha256(chunk), cursor - chunk.length, cursor));
    rest = remainder;
  }

  chunks.add(Chunk(_sha256(rest), cursor, cursor + rest.length));

  return chunks;
}

List<_MerkleNode> _generateLeaves(List<Chunk> chunks) {
  return chunks.map((c) {
    final id = _sha256Concat([
      _sha256(c.dataHash),
      _sha256(_intToBuffer(c.maxByteRange)),
    ]);
    return _MerkleNode(id, c.maxByteRange, _Leaf(c.dataHash));
  }).toList();
}

// Combina pares de nós adjacentes até restar só a raiz. Um nó ímpar sem par
// sobe direto pro próximo nível sem ser re-hasheado — mesmo comportamento
// de hashBranch/buildLayers em arweave-js.
_MerkleNode _buildLayers(List<_MerkleNode> nodes) {
  var layer = nodes;
  while (layer.length > 1) {
    final next = <_MerkleNode>[];
    var i = 0;
    while (i < layer.length) {
      final left = layer[i];
      if (i + 1 < layer.length) {
        final right = layer[i + 1];
        final id = _sha256Concat([
          _sha256(left.id),
          _sha256(right.id),
          _sha256(_intToBuffer(left.maxByteRange)),
        ]);
        next.add(_MerkleNode(id, right.maxByteRange, _Branch(left, right)));
        i += 2;
      } else {
        next.add(left);
        i += 1;
      }
    }
    layer = next;
  }
  return layer.first;
}

Uint8List computeDataRoot(List<Chunk> chunks) {
  final leaves = _generateLeaves(chunks);
  return _buildLayers(leaves).id;
}

// Prova de inclusão (data_path) de cada chunk na árvore, na mesma ordem de
// `chunks` (esquerda-pra-direita). Espelha resolveBranchProofs de
// arweave-js: a prova de um branch concatena os ids crus de 32 bytes dos
// filhos + intToBuffer do max_byte_range do filho esquerdo; a folha
// finaliza esse prefixo herdado com data_hash cru + intToBuffer(max_byte_range).
List<Proof> generateProofs(List<Chunk> chunks) {
  final root = _buildLayers(_generateLeaves(chunks));
  final out = <Proof>[];
  _resolveBranchProofs(root, Uint8List(0), out);
  return out;
}

// Risco de porte (não existe em Rust, onde ownership de Vec<u8> torna isso
// seguro por construção): List<int>/Uint8List em Dart são mutáveis e
// compartilháveis por referência. Se esta função mutasse `prefix` in-place
// (ex.: prefix.addAll(...)) e reaproveitasse o mesmo objeto pras duas
// chamadas recursivas, uma mutação da folha esquerda vazaria pra prova da
// direita silenciosamente — sem quebrar nenhum teste de shape, só
// produzindo data_path errado (precedente real: uma thread não resolvida
// no Swift Forums sobre exatamente esse tipo de bug portando essa mesma
// árvore). Mitigação: cada nível SEMPRE constrói uma cópia nova via spread
// (`[...prefix, ...]`), nunca estende o objeto recebido — `prefix` nunca é
// mutado, só lido, então as duas chamadas recursivas podem compartilhar a
// mesma referência de `extended` com segurança.
void _resolveBranchProofs(_MerkleNode node, Uint8List prefix, List<Proof> out) {
  final kind = node.kind;
  switch (kind) {
    case _Leaf(:final dataHash):
      final p = Uint8List.fromList([...prefix, ...dataHash, ..._intToBuffer(node.maxByteRange)]);
      final offset = node.maxByteRange > 0 ? node.maxByteRange - 1 : 0;
      out.add(Proof(offset, p));
    case _Branch(:final left, :final right):
      final extended = Uint8List.fromList(
          [...prefix, ...left.id, ...right.id, ..._intToBuffer(left.maxByteRange)]);
      _resolveBranchProofs(left, extended, out);
      _resolveBranchProofs(right, extended, out);
  }
}

// chunkData + generateProofs, já descartando o par (chunk, prova) final se
// o último chunk tiver 0 bytes (conteúdo múltiplo exato de maxChunkSize).
// Mesmo splice que generateTransactionChunks faz em arweave-js: esse chunk
// vazio existe só pra fechar a árvore de merkle corretamente, nunca deve
// ser upado via POST /chunk. Devolve também o dataRoot do conjunto de
// chunks completo (antes do descarte acima), reusando os hashes já
// calculados por chunkData — quem chama não precisa rechunkar/rehashear o
// conteúdo inteiro de novo só pra obter o mesmo root (mirror de
// chunk_data_for_upload em merkle.rs; achado do /code-review, Sessão 195).
(List<Chunk>, List<Proof>, Uint8List) chunkDataForUpload(Uint8List data) {
  final chunks = chunkData(data);
  final dataRoot = computeDataRoot(chunks);
  final proofs = generateProofs(chunks);
  if (chunks.length > 1) {
    final last = chunks.last;
    if (last.minByteRange == last.maxByteRange) {
      chunks.removeLast();
      proofs.removeLast();
    }
  }
  return (chunks, proofs, dataRoot);
}

int _bufferToUsize(Uint8List buffer) {
  var value = 0;
  for (final b in buffer) {
    // Multiplicação/soma em int nativo (64-bit) do Dart não checa overflow
    // por padrão — comportamento idêntico ao wrapping_mul/wrapping_add do
    // Rust, deliberado aqui (proteção contra um offset_buffer adversarial
    // de 32 bytes, muito maior que qualquer offset real de conteúdo).
    value = value * 256 + b;
  }
  return value;
}

// Verificação local de uma prova de merkle (data_path) contra um data_root
// — espelha validatePath de arweave-js. Usado como sanity check antes de
// cada POST /chunk: ArLocal não valida a prova que o cliente manda, então
// esse é o único jeito de pegar um bug sutil de generate_proofs antes de
// mainnet. Devolve (offset, leftBound, rightBound) do chunk provado se a
// prova for válida pro destino `dest`.
(int, int, int)? validatePath(
  Uint8List id,
  int dest,
  int leftBound,
  int rightBound,
  Uint8List path,
) {
  if (rightBound == 0) return null;

  if (dest >= rightBound) {
    return validatePath(id, 0, rightBound - 1, rightBound, path);
  }

  if (dest < 0) {
    return validatePath(id, 0, 0, rightBound, path);
  }

  if (path.length == _noteSize * 2) {
    final pathDataHash = path.sublist(0, _noteSize);
    final endOffsetBuffer = path.sublist(_noteSize, _noteSize * 2);
    final computed = _sha256Concat([_sha256(pathDataHash), _sha256(endOffsetBuffer)]);
    if (_bytesEqual(computed, id)) {
      return (rightBound - 1, leftBound, rightBound);
    }
    return null;
  }

  if (path.length < _noteSize * 3) return null;

  final left = path.sublist(0, _noteSize);
  final right = path.sublist(_noteSize, _noteSize * 2);
  final offsetBuffer = path.sublist(_noteSize * 2, _noteSize * 3);
  final offset = _bufferToUsize(offsetBuffer);
  final remainder = path.sublist(_noteSize * 3);

  final pathHash = _sha256Concat([_sha256(left), _sha256(right), _sha256(offsetBuffer)]);

  if (_bytesEqual(pathHash, id)) {
    if (dest < offset) {
      return validatePath(left, dest, leftBound, rightBound < offset ? rightBound : offset, remainder);
    }
    return validatePath(right, dest, leftBound > offset ? leftBound : offset, rightBound, remainder);
  }

  return null;
}

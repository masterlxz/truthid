use sha2::{Digest, Sha256};

/// Espelha `apps/arweave/src/ar_merkle.erl` / `arweave-js` `lib/merkle.ts` —
/// merkle tree sobre chunks do conteúdo, usado só pra derivar `data_root`.
/// Hash aqui é **SHA-256** (32 bytes) — distinto do SHA-384 do deep hash
/// (`deep_hash::deep_hash`), que assina a tx em si, não o conteúdo.
///
/// `MAX_CHUNK_SIZE`/`MIN_CHUNK_SIZE` são constantes de **protocolo** do
/// Arweave (mesmos valores de `arweave-js` `lib/merkle.ts`), não escolhas
/// deste código — não dá pra extrair numa constante compartilhada de
/// verdade entre Rust e Dart (sem pipeline de codegen cross-linguagem no
/// projeto), então o par tem que ser mantido manualmente em sincronia com
/// `mobile/lib/services/arweave_merkle.dart` (`maxChunkSize`/`minChunkSize`)
/// — se um dia o protocolo mudar esses valores, atualize os dois junto,
/// nunca só um (achado do `/code-review`, Sessão 195).
pub(crate) const MAX_CHUNK_SIZE: usize = 256 * 1024;
pub(crate) const MIN_CHUNK_SIZE: usize = 32 * 1024;
const NOTE_SIZE: usize = 32;

pub(crate) struct Chunk {
    pub data_hash: [u8; 32],
    pub min_byte_range: usize,
    pub max_byte_range: usize,
}

/// Árvore de merkle completa (não só a raiz) — necessário pra derivar a
/// prova de inclusão (`data_path`) de cada folha via `generate_proofs`, não
/// só o `data_root`. `compute_data_root` usa a mesma árvore e só lê `.id`
/// da raiz, comportamento inalterado.
enum NodeKind {
    Leaf { data_hash: [u8; 32] },
    Branch { left: Box<MerkleNode>, right: Box<MerkleNode> },
}

struct MerkleNode {
    id: [u8; 32],
    max_byte_range: usize,
    kind: NodeKind,
}

/// Prova de inclusão de um chunk na árvore (`data_path` do protocolo
/// Arweave) — usada no corpo do `POST /chunk`. `offset` é relativo à tx
/// (`0..data_size`), não ao weave inteiro.
pub(crate) struct Proof {
    pub offset: usize,
    pub proof: Vec<u8>,
}

fn sha256(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
}

fn sha256_concat(parts: &[&[u8]]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    for p in parts {
        hasher.update(p);
    }
    hasher.finalize().into()
}

/// Representação big-endian de 32 bytes de um offset — mesmo `intToBuffer`
/// de `arweave-js` (NOTE_SIZE = 32, não uma string decimal).
fn int_to_buffer(mut note: usize) -> [u8; NOTE_SIZE] {
    let mut buffer = [0u8; NOTE_SIZE];
    for i in (0..NOTE_SIZE).rev() {
        buffer[i] = (note % 256) as u8;
        note /= 256;
    }
    buffer
}

/// Divide `data` em chunks de até `MAX_CHUNK_SIZE`. Se o último chunk ficaria
/// menor que `MIN_CHUNK_SIZE`, rebalanceia dividindo o penúltimo chunk ao
/// meio — mesma lógica de `chunkData` em `arweave-js`. `data` vazio produz um
/// único chunk vazio (min=max=0), igual ao comportamento de referência.
pub(crate) fn chunk_data(data: &[u8]) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let mut rest = data;
    let mut cursor: usize = 0;

    while rest.len() >= MAX_CHUNK_SIZE {
        let mut chunk_size = MAX_CHUNK_SIZE;
        let next_chunk_size = rest.len() - MAX_CHUNK_SIZE;
        if next_chunk_size > 0 && next_chunk_size < MIN_CHUNK_SIZE {
            chunk_size = rest.len().div_ceil(2);
        }
        let (chunk, remainder) = rest.split_at(chunk_size);
        cursor += chunk.len();
        chunks.push(Chunk {
            data_hash: sha256(chunk),
            min_byte_range: cursor - chunk.len(),
            max_byte_range: cursor,
        });
        rest = remainder;
    }

    chunks.push(Chunk {
        data_hash: sha256(rest),
        min_byte_range: cursor,
        max_byte_range: cursor + rest.len(),
    });

    chunks
}

fn generate_leaves(chunks: &[Chunk]) -> Vec<MerkleNode> {
    chunks
        .iter()
        .map(|c| MerkleNode {
            id: sha256_concat(&[
                &sha256(&c.data_hash),
                &sha256(&int_to_buffer(c.max_byte_range)),
            ]),
            max_byte_range: c.max_byte_range,
            kind: NodeKind::Leaf { data_hash: c.data_hash },
        })
        .collect()
}

/// Combina pares de nós adjacentes até restar só a raiz. Um nó ímpar sem
/// par (`right` ausente) sobe direto pro próximo nível sem ser re-hasheado
/// — mesmo comportamento de `hashBranch`/`buildLayers` em `arweave-js`.
fn build_layers(mut nodes: Vec<MerkleNode>) -> MerkleNode {
    while nodes.len() > 1 {
        let mut next_layer = Vec::with_capacity(nodes.len().div_ceil(2));
        let mut iter = nodes.into_iter();
        while let Some(left) = iter.next() {
            match iter.next() {
                Some(right) => {
                    let id = sha256_concat(&[
                        &sha256(&left.id),
                        &sha256(&right.id),
                        &sha256(&int_to_buffer(left.max_byte_range)),
                    ]);
                    let max_byte_range = right.max_byte_range;
                    next_layer.push(MerkleNode {
                        id,
                        max_byte_range,
                        kind: NodeKind::Branch { left: Box::new(left), right: Box::new(right) },
                    });
                }
                None => next_layer.push(left),
            }
        }
        nodes = next_layer;
    }
    nodes.into_iter().next().expect("chunk_data nunca produz lista vazia")
}

/// `data_root` — raiz da merkle tree sobre os chunks do conteúdo.
pub(crate) fn compute_data_root(chunks: &[Chunk]) -> [u8; 32] {
    let leaves = generate_leaves(chunks);
    build_layers(leaves).id
}

/// Prova de inclusão (`data_path`) de cada chunk na árvore, na mesma ordem
/// de `chunks` (esquerda-pra-direita). Espelha `resolveBranchProofs` de
/// `arweave-js` (`lib/merkle.ts`): a prova de um branch concatena os ids
/// **crus** de 32 bytes dos filhos (sem re-hashear — o duplo-sha256 já
/// aplicado em `generate_leaves`/`build_layers` é só pra computar o id de
/// cada nó, nunca reaplicado ao serializar esse id numa prova ancestral) +
/// `int_to_buffer` do `max_byte_range` do filho esquerdo; a folha finaliza
/// esse prefixo herdado com `data_hash` cru + `int_to_buffer(max_byte_range)`.
pub(crate) fn generate_proofs(chunks: &[Chunk]) -> Vec<Proof> {
    let root = build_layers(generate_leaves(chunks));
    let mut out = Vec::with_capacity(chunks.len());
    resolve_branch_proofs(&root, Vec::new(), &mut out);
    out
}

fn resolve_branch_proofs(node: &MerkleNode, proof: Vec<u8>, out: &mut Vec<Proof>) {
    match &node.kind {
        NodeKind::Leaf { data_hash } => {
            let mut p = proof;
            p.extend_from_slice(data_hash);
            p.extend_from_slice(&int_to_buffer(node.max_byte_range));
            out.push(Proof { offset: node.max_byte_range.saturating_sub(1), proof: p });
        }
        NodeKind::Branch { left, right } => {
            let mut p = proof;
            p.extend_from_slice(&left.id);
            p.extend_from_slice(&right.id);
            p.extend_from_slice(&int_to_buffer(left.max_byte_range));
            resolve_branch_proofs(left, p.clone(), out);
            resolve_branch_proofs(right, p, out);
        }
    }
}

/// `chunk_data` + `generate_proofs`, já descartando o par (chunk, prova)
/// final se o último chunk tiver 0 bytes (conteúdo múltiplo exato de
/// `MAX_CHUNK_SIZE` — ver `exactly_max_chunk_size_produces_two_chunks`).
/// Mesmo splice que `generateTransactionChunks` faz em `arweave-js`: esse
/// chunk vazio existe só pra fechar a árvore de merkle corretamente, nunca
/// deve ser upado via `POST /chunk`. Devolve também o `data_root` do
/// conjunto de chunks **completo** (antes do descarte acima — o chunk vazio
/// final continua fazendo parte da árvore mesmo não sendo upado), computado
/// aqui reusando os hashes já calculados por `chunk_data`, pra quem chama
/// não precisar rechunkar/rehashear o conteúdo inteiro de novo só pra obter
/// o mesmo root (ver `try_resume`, que consumia isso via `chunk_data(content)`
/// duplicado — achado do `/code-review`, Sessão 195).
pub(crate) fn chunk_data_for_upload(data: &[u8]) -> (Vec<Chunk>, Vec<Proof>, [u8; 32]) {
    let mut chunks = chunk_data(data);
    let data_root = compute_data_root(&chunks);
    let mut proofs = generate_proofs(&chunks);
    if chunks.len() > 1 {
        if let Some(last) = chunks.last() {
            if last.min_byte_range == last.max_byte_range {
                chunks.pop();
                proofs.pop();
            }
        }
    }
    (chunks, proofs, data_root)
}

fn buffer_to_usize(buffer: &[u8]) -> usize {
    let mut value: usize = 0;
    for &b in buffer {
        value = value.wrapping_mul(256).wrapping_add(b as usize);
    }
    value
}

/// Verificação local de uma prova de merkle (`data_path`) contra um
/// `data_root` — espelha `validatePath` de `arweave-js` (`lib/merkle.ts`).
/// Usado como sanity check antes de cada `POST /chunk` (mesmo padrão que
/// `verify_transaction_signature` já usa antes de `submit_transaction`):
/// ArLocal não valida a prova que o cliente manda, então esse é o único jeito
/// de pegar um bug sutil na construção de `generate_proofs` antes de mainnet.
/// Devolve `Some((offset, left_bound, right_bound))` do chunk provado se a
/// prova for válida pro destino `dest`.
pub(crate) fn validate_path(
    id: &[u8],
    dest: i64,
    left_bound: usize,
    right_bound: usize,
    path: &[u8],
) -> Option<(usize, usize, usize)> {
    if right_bound == 0 {
        return None;
    }

    if dest >= right_bound as i64 {
        return validate_path(id, 0, right_bound - 1, right_bound, path);
    }

    if dest < 0 {
        return validate_path(id, 0, 0, right_bound, path);
    }

    if path.len() == NOTE_SIZE * 2 {
        let path_data_hash = &path[0..NOTE_SIZE];
        let end_offset_buffer = &path[NOTE_SIZE..NOTE_SIZE * 2];
        let computed = sha256_concat(&[&sha256(path_data_hash), &sha256(end_offset_buffer)]);
        if computed.as_slice() == id {
            return Some((right_bound - 1, left_bound, right_bound));
        }
        return None;
    }

    if path.len() < NOTE_SIZE * 3 {
        return None;
    }

    let left = &path[0..NOTE_SIZE];
    let right = &path[NOTE_SIZE..NOTE_SIZE * 2];
    let offset_buffer = &path[NOTE_SIZE * 2..NOTE_SIZE * 3];
    let offset = buffer_to_usize(offset_buffer);
    let remainder = &path[NOTE_SIZE * 3..];

    let path_hash = sha256_concat(&[&sha256(left), &sha256(right), &sha256(offset_buffer)]);

    if path_hash.as_slice() == id {
        if dest < offset as i64 {
            return validate_path(left, dest, left_bound, right_bound.min(offset), remainder);
        }
        return validate_path(right, dest, left_bound.max(offset), right_bound, remainder);
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_data_produces_one_zero_length_chunk() {
        let chunks = chunk_data(&[]);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].min_byte_range, 0);
        assert_eq!(chunks[0].max_byte_range, 0);
    }

    #[test]
    fn small_data_produces_one_chunk() {
        let data = vec![7u8; 1024];
        let chunks = chunk_data(&data);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].max_byte_range, 1024);
    }

    #[test]
    fn exactly_max_chunk_size_produces_two_chunks() {
        // MAX_CHUNK_SIZE bytes entram no loop (rest.len() >= MAX), sobra um
        // chunk vazio no final (mesmo comportamento do arweave-js).
        let data = vec![1u8; MAX_CHUNK_SIZE];
        let chunks = chunk_data(&data);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].max_byte_range, MAX_CHUNK_SIZE);
        assert_eq!(chunks[1].min_byte_range, MAX_CHUNK_SIZE);
        assert_eq!(chunks[1].max_byte_range, MAX_CHUNK_SIZE);
    }

    #[test]
    fn slightly_over_max_chunk_size_rebalances_to_avoid_tiny_last_chunk() {
        // MAX_CHUNK_SIZE + 1 byte deixaria o último chunk com 1 byte
        // (< MIN_CHUNK_SIZE) — deve rebalancear dividindo ao meio.
        let data = vec![1u8; MAX_CHUNK_SIZE + 1];
        let chunks = chunk_data(&data);
        assert_eq!(chunks.len(), 2);
        for c in &chunks {
            let len = c.max_byte_range - c.min_byte_range;
            assert!(len >= MIN_CHUNK_SIZE, "chunk de {len} bytes abaixo do mínimo");
        }
        assert_eq!(chunks.last().unwrap().max_byte_range, data.len());
    }

    #[test]
    fn multi_chunk_byte_ranges_are_contiguous() {
        let data = vec![9u8; MAX_CHUNK_SIZE * 3 + 500];
        let chunks = chunk_data(&data);
        assert!(chunks.len() >= 3);
        let mut expected_start = 0;
        for c in &chunks {
            assert_eq!(c.min_byte_range, expected_start);
            expected_start = c.max_byte_range;
        }
        assert_eq!(chunks.last().unwrap().max_byte_range, data.len());
    }

    #[test]
    fn data_root_is_deterministic() {
        let data = b"hello vault blob".to_vec();
        let root1 = compute_data_root(&chunk_data(&data));
        let root2 = compute_data_root(&chunk_data(&data));
        assert_eq!(root1, root2);
    }

    #[test]
    fn different_data_different_root() {
        let root1 = compute_data_root(&chunk_data(b"vault v1"));
        let root2 = compute_data_root(&chunk_data(b"vault v2"));
        assert_ne!(root1, root2);
    }

    // Vetor cross-checado contra `arweave-js` (`computeRootHash`) pra um
    // conteúdo pequeno (1 chunk) — ver deep_hash.rs pra explicação da técnica.
    #[test]
    fn cross_checked_single_chunk_root() {
        let root = compute_data_root(&chunk_data(b"hello world"));
        assert_eq!(hex::encode(root), CROSS_CHECKED_SINGLE_CHUNK_ROOT_HEX);
    }

    // Vetor cross-checado multi-chunk (MAX_CHUNK_SIZE*2 + 500 bytes de
    // conteúdo determinístico) — exercita build_layers com >2 folhas.
    #[test]
    fn cross_checked_multi_chunk_root() {
        let data = vec![0xABu8; MAX_CHUNK_SIZE * 2 + 500];
        let root = compute_data_root(&chunk_data(&data));
        assert_eq!(hex::encode(root), CROSS_CHECKED_MULTI_CHUNK_ROOT_HEX);
    }

    const CROSS_CHECKED_SINGLE_CHUNK_ROOT_HEX: &str =
        "27780e22e3b3f356e8aba78732ce3217ce1f312874cafaca16a39c9d740c2fdd";
    const CROSS_CHECKED_MULTI_CHUNK_ROOT_HEX: &str =
        "fb70bd611bd95db03ae5e779316bc16940493b636908d7e4b9a90d837dcfa947";

    // Vetor cross-checado contra `arweave-js` real (`generateTransactionChunks`,
    // pacote `arweave` instalado num scratchpad descartável) — mesmo conteúdo
    // de `cross_checked_multi_chunk_root` (3 chunks reais, sem trailing vazio:
    // 256KiB + ~128KiB rebalanceado + ~128KiB). Prova que `generate_proofs`
    // produz os mesmos bytes de `data_path` que o cliente de referência, não
    // só que a árvore reassembla localmente.
    #[test]
    fn cross_checked_proofs_match_arweave_js() {
        let data = vec![0xABu8; MAX_CHUNK_SIZE * 2 + 500];
        let (chunks, proofs, _root) = chunk_data_for_upload(&data);
        assert_eq!(chunks.len(), 3, "conteúdo não é múltiplo exato — não deve descartar nada");
        assert_eq!(proofs.len(), 3);

        assert_eq!(proofs[0].offset, 262_143);
        assert_eq!(hex::encode(&proofs[0].proof), CROSS_CHECKED_PROOF_0_HEX);
        assert_eq!(proofs[1].offset, 393_465);
        assert_eq!(hex::encode(&proofs[1].proof), CROSS_CHECKED_PROOF_1_HEX);
        assert_eq!(proofs[2].offset, 524_787);
        assert_eq!(hex::encode(&proofs[2].proof), CROSS_CHECKED_PROOF_2_HEX);
    }

    #[test]
    fn chunk_data_for_upload_discards_trailing_empty_chunk() {
        // Múltiplo exato de MAX_CHUNK_SIZE: chunk_data() cru produz 2 chunks
        // (o segundo vazio, ver exactly_max_chunk_size_produces_two_chunks).
        // chunk_data_for_upload deve descartar esse par, sobrando 1 — mesmo
        // resultado que `generateTransactionChunks` real (confirmado via
        // node: num_chunks_after_discard: 1 pro mesmo tamanho de conteúdo).
        let data = vec![0x11u8; MAX_CHUNK_SIZE];
        let (chunks, proofs, root) = chunk_data_for_upload(&data);
        assert_eq!(chunks.len(), 1);
        assert_eq!(proofs.len(), 1);
        assert_eq!(chunks[0].max_byte_range, MAX_CHUNK_SIZE);
        // O root devolvido é da árvore completa (2 chunks, incluindo o vazio
        // descartado do upload) — precisa bater com compute_data_root sobre
        // o chunk_data() cru, não sobre os chunks já trimados.
        assert_eq!(root, compute_data_root(&chunk_data(&data)));
    }

    #[test]
    fn chunk_data_for_upload_keeps_non_exact_multiple_chunks() {
        let data = vec![0xABu8; MAX_CHUNK_SIZE * 2 + 500];
        let (chunks, proofs, root) = chunk_data_for_upload(&data);
        assert_eq!(chunks.len(), 3);
        assert_eq!(proofs.len(), 3);
        assert_eq!(root, compute_data_root(&chunk_data(&data)));
    }

    #[test]
    fn validate_path_accepts_proof_generated_by_this_module() {
        let data = vec![0xABu8; MAX_CHUNK_SIZE * 2 + 500];
        let (chunks, proofs, root) = chunk_data_for_upload(&data);

        for (chunk, proof) in chunks.iter().zip(proofs.iter()) {
            let result = validate_path(&root, proof.offset as i64, 0, data.len(), &proof.proof);
            let (offset, left_bound, right_bound) =
                result.expect("prova gerada por generate_proofs deveria validar");
            assert_eq!(offset, chunk.max_byte_range - 1);
            assert_eq!(left_bound, chunk.min_byte_range);
            assert_eq!(right_bound, chunk.max_byte_range);
        }
    }

    #[test]
    fn validate_path_rejects_tampered_proof() {
        let data = vec![0xABu8; MAX_CHUNK_SIZE * 2 + 500];
        let (_chunks, proofs, root) = chunk_data_for_upload(&data);

        let mut tampered = proofs[0].proof.clone();
        tampered[0] ^= 0xFF;
        assert!(validate_path(&root, proofs[0].offset as i64, 0, data.len(), &tampered).is_none());
    }

    const CROSS_CHECKED_PROOF_0_HEX: &str = "84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa021304c16b5b3b0ac94b52784caf6c0f6f7fa76eacb9b4295087edc9da297b01bbf5dd864466f45523652fe3d6051cea17a669d863936d26f170964da1a47ffc0000000000000000000000000000000000000000000000000000000000040000c6a68609e7e9bf598a7e12a826337bd08f29200bc8c37f0c4ebe26b7dfc8c4be0000000000000000000000000000000000000000000000000000000000040000";
    const CROSS_CHECKED_PROOF_1_HEX: &str = "84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa021304c16b5b3b0ac94b52784caf6c0f6f7fa76eacb9b4295087edc9da297b01bbf5dd864466f45523652fe3d6051cea17a669d863936d26f170964da1a47ffc00000000000000000000000000000000000000000000000000000000000400003ccde55fefef16e9aed69a5af49173818df5f730f6c08f0ee74c7217cdb96f4500000000000000000000000000000000000000000000000000000000000600fa";
    const CROSS_CHECKED_PROOF_2_HEX: &str = "84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa3ccde55fefef16e9aed69a5af49173818df5f730f6c08f0ee74c7217cdb96f4500000000000000000000000000000000000000000000000000000000000801f4";
}

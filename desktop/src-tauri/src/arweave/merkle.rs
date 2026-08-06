use sha2::{Digest, Sha256};

/// Espelha `apps/arweave/src/ar_merkle.erl` / `arweave-js` `lib/merkle.ts` —
/// merkle tree sobre chunks do conteúdo, usado só pra derivar `data_root`.
/// Hash aqui é **SHA-256** (32 bytes) — distinto do SHA-384 do deep hash
/// (`deep_hash::deep_hash`), que assina a tx em si, não o conteúdo.
pub(crate) const MAX_CHUNK_SIZE: usize = 256 * 1024;
pub(crate) const MIN_CHUNK_SIZE: usize = 32 * 1024;
const NOTE_SIZE: usize = 32;

pub(crate) struct Chunk {
    pub data_hash: [u8; 32],
    // Não lido nesta etapa (só `data_root` é usado) — necessário pro upload
    // em chunks via `POST /chunk` de documentos grandes, fora de escopo (ver
    // risco #5 do plano). Mantido pra não recalcular o chunking depois.
    #[allow(dead_code)]
    pub min_byte_range: usize,
    pub max_byte_range: usize,
}

struct Node {
    id: [u8; 32],
    max_byte_range: usize,
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

fn generate_leaves(chunks: &[Chunk]) -> Vec<Node> {
    chunks
        .iter()
        .map(|c| Node {
            id: sha256_concat(&[
                &sha256(&c.data_hash),
                &sha256(&int_to_buffer(c.max_byte_range)),
            ]),
            max_byte_range: c.max_byte_range,
        })
        .collect()
}

/// Combina pares de nós adjacentes até restar só a raiz. Um nó ímpar sem
/// par (`right` ausente) sobe direto pro próximo nível sem ser re-hasheado
/// — mesmo comportamento de `hashBranch`/`buildLayers` em `arweave-js`.
fn build_layers(mut nodes: Vec<Node>) -> Node {
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
                    next_layer.push(Node {
                        id,
                        max_byte_range: right.max_byte_range,
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
}

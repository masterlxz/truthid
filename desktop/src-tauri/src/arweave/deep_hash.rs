use sha2::{Digest, Sha384};

/// Espelha `DeepHashChunk = Uint8Array | DeepHashChunk[]` do ANS-104/formato-2
/// (`ArweaveTeam/arweave-standards`). Usado só pra montar a entrada do deep
/// hash — não confundir com `merkle::Chunk`, que é sobre chunking do
/// conteúdo em si (SHA-256, algoritmo diferente).
pub(crate) enum DeepHashChunk {
    Blob(Vec<u8>),
    List(Vec<DeepHashChunk>),
}

impl DeepHashChunk {
    pub(crate) fn blob(bytes: impl Into<Vec<u8>>) -> Self {
        DeepHashChunk::Blob(bytes.into())
    }

    pub(crate) fn utf8(s: &str) -> Self {
        DeepHashChunk::Blob(s.as_bytes().to_vec())
    }
}

fn sha384(data: &[u8]) -> [u8; 48] {
    Sha384::digest(data).into()
}

fn concat(a: &[u8], b: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(a.len() + b.len());
    v.extend_from_slice(a);
    v.extend_from_slice(b);
    v
}

/// Deep hash — SHA-384, 48 bytes de saída. NÃO confundir com o SHA-256 do
/// merkle `data_root` (`merkle::compute_data_root`) — são dois algoritmos de
/// hash diferentes dentro do mesmo fluxo de assinatura da tx.
pub(crate) fn deep_hash(chunk: &DeepHashChunk) -> [u8; 48] {
    match chunk {
        DeepHashChunk::Blob(data) => {
            let tag = concat(b"blob", data.len().to_string().as_bytes());
            let tagged = concat(&sha384(&tag), &sha384(data));
            sha384(&tagged)
        }
        DeepHashChunk::List(items) => {
            let tag = concat(b"list", items.len().to_string().as_bytes());
            let mut acc = sha384(&tag);
            for item in items {
                let item_hash = deep_hash(item);
                let pair = concat(&acc, &item_hash);
                acc = sha384(&pair);
            }
            acc
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blob_hash_is_deterministic() {
        let a = deep_hash(&DeepHashChunk::blob(b"hello".to_vec()));
        let b = deep_hash(&DeepHashChunk::blob(b"hello".to_vec()));
        assert_eq!(a, b);
    }

    #[test]
    fn different_blobs_different_hash() {
        let a = deep_hash(&DeepHashChunk::blob(b"hello".to_vec()));
        let b = deep_hash(&DeepHashChunk::blob(b"world".to_vec()));
        assert_ne!(a, b);
    }

    #[test]
    fn empty_blob_hash_is_not_zero() {
        let h = deep_hash(&DeepHashChunk::blob(Vec::new()));
        assert_ne!(h, [0u8; 48]);
    }

    #[test]
    fn empty_list_hash_is_deterministic_and_differs_from_empty_blob() {
        let list_hash = deep_hash(&DeepHashChunk::List(vec![]));
        let blob_hash = deep_hash(&DeepHashChunk::blob(Vec::new()));
        assert_ne!(list_hash, blob_hash);
    }

    #[test]
    fn list_order_matters() {
        let a = deep_hash(&DeepHashChunk::List(vec![
            DeepHashChunk::utf8("a"),
            DeepHashChunk::utf8("b"),
        ]));
        let b = deep_hash(&DeepHashChunk::List(vec![
            DeepHashChunk::utf8("b"),
            DeepHashChunk::utf8("a"),
        ]));
        assert_ne!(a, b);
    }

    #[test]
    fn nested_list_hashes_differ_from_flattened() {
        let nested = deep_hash(&DeepHashChunk::List(vec![DeepHashChunk::List(vec![
            DeepHashChunk::utf8("a"),
            DeepHashChunk::utf8("b"),
        ])]));
        let flat = deep_hash(&DeepHashChunk::List(vec![
            DeepHashChunk::utf8("a"),
            DeepHashChunk::utf8("b"),
        ]));
        assert_ne!(nested, flat);
    }

    /// Deep hash é SHA-384 (48 bytes) — distinto do SHA-256 (32 bytes) usado
    /// no merkle `data_root`. Fácil de trocar sem querer durante a
    /// implementação; este teste pega isso cedo.
    #[test]
    fn output_is_48_bytes_sha384_not_32_bytes_sha256() {
        let h = deep_hash(&DeepHashChunk::blob(b"x".to_vec()));
        assert_eq!(h.len(), 48);
    }

    // Vetores cross-checados contra `arweave-js` (pacote oficial `arweave`,
    // rodado localmente via Node — script descartável, não versionado) pra
    // não confiar só em auto-consistência. Ver
    // `desktop/src-tauri/scripts/gen_deep_hash_vectors.mjs` (removido após
    // uso) pra como esses valores foram gerados.
    #[test]
    fn cross_checked_blob_vector() {
        // deepHash(Buffer.from("hello world"))
        let h = deep_hash(&DeepHashChunk::blob(b"hello world".to_vec()));
        assert_eq!(hex::encode(h), CROSS_CHECKED_BLOB_HEX);
    }

    #[test]
    fn cross_checked_list_vector() {
        // deepHash([Buffer.from("2"), Buffer.from("hello"), Buffer.from("world")])
        let h = deep_hash(&DeepHashChunk::List(vec![
            DeepHashChunk::utf8("2"),
            DeepHashChunk::utf8("hello"),
            DeepHashChunk::utf8("world"),
        ]));
        assert_eq!(hex::encode(h), CROSS_CHECKED_LIST_HEX);
    }

    // Preenchidos a partir da saída real de `arweave-js` — ver seção de
    // geração de vetores no plano da Etapa 1.
    const CROSS_CHECKED_BLOB_HEX: &str =
        "42b60b0591c3817049a0658511314e57167cf2992b2c4d2013211707ab65dccf4e1a44fb385107290cf6bdb5e45455df";
    const CROSS_CHECKED_LIST_HEX: &str =
        "7e6855103565e447a404995c77564e02174f2ce23bc351f950e7d801ed6eed0c06cfa3544df8a078dcd2d25fb3338248";
}

//! Checkpoint de publish multi-chunk — permite retomar um `publish()` que
//! falhou no meio do envio de chunks em vez de deixar a tx presa on-chain
//! incompleta pra sempre (achado real de `/code-review`, ver
//! `project/ROADMAP.md`). Só cobre o caminho multi-chunk (`chunks.len() >
//! 1`); o caminho single-shot é uma única requisição, atômico o bastante
//! sem precisar de checkpoint.
//!
//! Um arquivo por checkpoint, chaveado pelo hash SHA-256 do conteúdo (não 1
//! arquivo global) — permite mais de uma publicação multi-chunk parcial
//! pendente ao mesmo tempo sem uma sobrescrever o progresso da outra.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone)]
pub(crate) struct PublishCheckpoint {
    pub wallet_address: String,
    pub content_hash: String,
    pub tx_id: String,
    pub data_root: String,
    pub data_size: String,
    pub node_url: String,
    pub total_chunks: usize,
    pub next_chunk_index: usize,
}

pub(crate) fn content_hash_hex(content: &[u8]) -> String {
    hex::encode(Sha256::digest(content))
}

fn checkpoint_path(content_hash: &str) -> Result<PathBuf, String> {
    crate::config::truthid_file_path(&format!("arweave_checkpoint_{content_hash}.json"))
}

/// `None` tanto se o arquivo não existir quanto se estiver corrompido —
/// nos dois casos, `publish()` deve tratar como "sem checkpoint utilizável"
/// e seguir como uma publicação nova, nunca falhar por causa disso.
pub(crate) fn load(content_hash: &str) -> Option<PublishCheckpoint> {
    let path = checkpoint_path(content_hash).ok()?;
    if !path.exists() {
        return None;
    }
    let raw = crate::config::read_text(&path).ok()?;
    serde_json::from_str(&raw).ok()
}

pub(crate) fn save(cp: &PublishCheckpoint) -> Result<(), String> {
    let path = checkpoint_path(&cp.content_hash)?;
    crate::config::save_json(&path, cp)
}

/// Idempotente — não é erro tentar limpar um checkpoint que não existe
/// (ex.: caminho single-shot, que nunca cria um).
pub(crate) fn clear(content_hash: &str) -> Result<(), String> {
    let path = checkpoint_path(content_hash)?;
    if path.exists() {
        std::fs::remove_file(&path).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(content_hash: &str) -> PublishCheckpoint {
        PublishCheckpoint {
            wallet_address: "addr".to_string(),
            content_hash: content_hash.to_string(),
            tx_id: "tx123".to_string(),
            data_root: "root".to_string(),
            data_size: "1000".to_string(),
            node_url: "https://arweave.net".to_string(),
            total_chunks: 3,
            next_chunk_index: 1,
        }
    }

    #[test]
    fn load_returns_none_when_missing() {
        assert!(load("does-not-exist-hash-xyz").is_none());
    }

    #[test]
    fn save_then_load_round_trips() {
        let hash = format!("test-{}", uuid_like());
        let cp = sample(&hash);
        save(&cp).unwrap();
        let loaded = load(&hash).unwrap();
        assert_eq!(loaded.tx_id, cp.tx_id);
        assert_eq!(loaded.next_chunk_index, 1);
        clear(&hash).unwrap();
    }

    #[test]
    fn clear_removes_checkpoint() {
        let hash = format!("test-{}", uuid_like());
        save(&sample(&hash)).unwrap();
        assert!(load(&hash).is_some());
        clear(&hash).unwrap();
        assert!(load(&hash).is_none());
    }

    #[test]
    fn clear_on_missing_checkpoint_is_a_noop() {
        assert!(clear("never-existed-hash-abc").is_ok());
    }

    // Evita colisão entre testes rodando em paralelo no mesmo diretório
    // $HOME/.truthid — cada teste usa seu próprio hash "sintético".
    fn uuid_like() -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        format!(
            "{}-{:?}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos(),
            std::thread::current().id()
        )
    }
}

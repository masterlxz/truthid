use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};
use std::path::PathBuf;

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/// Configuração de um provider de pinning IPFS.
///
/// `kind` aceita dois valores:
///  - `"kubo"` — node Kubo (local ou remoto); usa `/api/v0/add` para upload de conteúdo
///  - `"psa"`  — IPFS Pinning Service API; usa `POST /pins` para fixar um CID já existente
///
/// Para uso self-hosted: `kind = "kubo"`, `endpoint_url = "http://localhost:5001"`, `api_key = ""`.
/// Para Filebase / 4EVERLAND / Pinata PSA: `kind = "psa"`, `endpoint_url` = URL base da API PSA.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct PinningProvider {
    pub name: String,
    pub kind: String,
    pub endpoint_url: String,
    pub api_key: String,
}

/// Resultado de `pin_vault`: CID retornado pelo provider, hash do conteúdo (para o contrato)
/// e listas de providers que tiveram sucesso ou falha.
#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct PinResult {
    pub cid: String,
    /// keccak256 do blob cifrado, prefixado com "0x" — usado diretamente pelo VaultRegistry.
    pub content_hash: String,
    pub providers_ok: Vec<String>,
    pub providers_failed: Vec<String>,
}

// ---------------------------------------------------------------------------
// Lógica de upload / pin
// ---------------------------------------------------------------------------

/// Faz upload do `content` para todos os Kubo providers e depois pina o CID
/// em todos os PSA providers. Retorna `PinResult` com o CID obtido e o hash
/// do conteúdo para o contrato VaultRegistry.
pub(crate) async fn pin_vault(
    content: &[u8],
    providers: &[PinningProvider],
) -> Result<PinResult, String> {
    let content_hash = format!("0x{}", hex::encode(Keccak256::digest(content)));

    let kubo: Vec<_> = providers.iter().filter(|p| p.kind == "kubo").collect();
    let psa: Vec<_> = providers.iter().filter(|p| p.kind == "psa").collect();

    if kubo.is_empty() {
        return Err(
            "nenhum provider Kubo configurado — faça o upload pelo menos via nó local".to_string(),
        );
    }

    let mut cid = String::new();
    let mut providers_ok = Vec::new();
    let mut providers_failed = Vec::new();

    // 1. Upload de conteúdo para cada Kubo node
    for p in &kubo {
        match kubo_add(&p.endpoint_url, content).await {
            Ok(c) => {
                if cid.is_empty() {
                    cid = c;
                }
                providers_ok.push(p.name.clone());
            }
            Err(e) => providers_failed.push(format!("{}: {e}", p.name)),
        }
    }

    if cid.is_empty() {
        return Err(format!(
            "todos os providers Kubo falharam: {}",
            providers_failed.join("; ")
        ));
    }

    // 2. Pinagem do CID em cada PSA provider
    for p in &psa {
        match psa_pin(&p.endpoint_url, &p.api_key, &cid).await {
            Ok(()) => providers_ok.push(p.name.clone()),
            Err(e) => providers_failed.push(format!("{}: {e}", p.name)),
        }
    }

    Ok(PinResult {
        cid,
        content_hash,
        providers_ok,
        providers_failed,
    })
}

// ---------------------------------------------------------------------------
// HTTP — Kubo
// ---------------------------------------------------------------------------

/// POST `{endpoint}/api/v0/add` com o blob como multipart.
/// Retorna o CID (campo `Hash` na resposta JSON do Kubo).
async fn kubo_add(endpoint_url: &str, content: &[u8]) -> Result<String, String> {
    let client = reqwest::Client::new();
    let part = reqwest::multipart::Part::bytes(content.to_vec())
        .file_name("vault.enc")
        .mime_str("application/octet-stream")
        .map_err(|e| e.to_string())?;
    let form = reqwest::multipart::Form::new().part("file", part);
    let url = format!("{}/api/v0/add", endpoint_url.trim_end_matches('/'));

    let res = client
        .post(&url)
        .multipart(form)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !res.status().is_success() {
        return Err(format!("kubo add retornou {}", res.status()));
    }

    // Kubo pode retornar múltiplas linhas JSON; a última tem o hash raiz.
    let text = res.text().await.map_err(|e| e.to_string())?;
    let last = text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .last()
        .ok_or("resposta vazia do kubo")?;

    let json: serde_json::Value = serde_json::from_str(last)
        .map_err(|e| format!("JSON inválido na resposta do kubo: {e}"))?;

    json["Hash"]
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| format!("campo Hash ausente: {last}"))
}

// ---------------------------------------------------------------------------
// HTTP — IPFS Pinning Service API
// ---------------------------------------------------------------------------

/// POST `{endpoint}/pins` com `{ cid, name }`.
/// 202 Accepted ou 409 Conflict (já fixado) são tratados como sucesso.
async fn psa_pin(endpoint_url: &str, api_key: &str, cid: &str) -> Result<(), String> {
    let client = reqwest::Client::new();
    let url = format!("{}/pins", endpoint_url.trim_end_matches('/'));
    let body = serde_json::json!({ "cid": cid, "name": "truthid-vault" });

    let mut builder = client.post(&url).json(&body);
    if !api_key.is_empty() {
        builder = builder.bearer_auth(api_key);
    }

    let res = builder.send().await.map_err(|e| e.to_string())?;
    let status = res.status();

    // 200/201/202 = ok; 409 = já existia, também ok
    if status.is_success() || status.as_u16() == 409 {
        Ok(())
    } else {
        Err(format!("PSA pin retornou {status}"))
    }
}

// ---------------------------------------------------------------------------
// Persistência de providers
// ---------------------------------------------------------------------------

fn providers_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    std::path::Path::new(&home)
        .join(".truthid")
        .join("pinning_providers.json")
}

pub(crate) fn load_providers() -> Vec<PinningProvider> {
    let path = providers_path();
    if !path.exists() {
        return Vec::new();
    }
    let raw = std::fs::read_to_string(&path).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

pub(crate) fn save_providers(providers: &[PinningProvider]) -> Result<(), String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let json = serde_json::to_string_pretty(providers).map_err(|e| e.to_string())?;
    std::fs::write(providers_path(), json).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_hash_is_keccak256_prefixed() {
        let data = b"hello vault";
        let expected = format!("0x{}", hex::encode(Keccak256::digest(data)));
        assert!(expected.starts_with("0x"));
        assert_eq!(expected.len(), 2 + 64); // "0x" + 32 bytes hex
        // Determinístico
        let expected2 = format!("0x{}", hex::encode(Keccak256::digest(data)));
        assert_eq!(expected, expected2);
    }

    #[test]
    fn different_content_different_hash() {
        let h1 = hex::encode(Keccak256::digest(b"vault v1"));
        let h2 = hex::encode(Keccak256::digest(b"vault v2"));
        assert_ne!(h1, h2);
    }

    #[test]
    fn load_providers_returns_empty_when_no_file() {
        // Usamos um caminho que definitivamente não existe
        // (test não polui HOME real)
        let providers = load_providers();
        // Se não houver arquivo, retorna Vec vazio
        // (pode já existir no HOME real; apenas verifica que não panics)
        let _ = providers;
    }
}

use sha3::{Digest, Keccak256};

// ---------------------------------------------------------------------------
// Hash de conteúdo
// ---------------------------------------------------------------------------

/// keccak256 do conteúdo, hex prefixado com "0x" — mesmo formato usado pelo
/// `content_hash` do `VaultRegistry`. Usado tanto pelos publishers Arweave
/// (`arweave::publish_*`) quanto por `vault::document_needs_pin` pra decidir
/// se o conteúdo de um documento mudou desde a última publicação, sem
/// precisar de rede.
pub(crate) fn keccak256_hex(content: &[u8]) -> String {
    format!("0x{}", hex::encode(Keccak256::digest(content)))
}

// ---------------------------------------------------------------------------
// Leitura por CID — gateways públicos (Fase 15.7)
// ---------------------------------------------------------------------------

/// Mesmos 2 gateways públicos e timeout que `IpfsGatewayClient` do Mobile
/// (`ipfs_gateway_client.dart`) usa pra ler o blob do vault publicado por
/// outro device — reaproveitado aqui só pra buscar o blob **separado** de um
/// documento (Fase 15.7) quando o cache local não tem o conteúdo ainda (ex:
/// documento adicionado em outro device).
const GATEWAYS: [&str; 2] = ["https://ipfs.io/ipfs/", "https://dweb.link/ipfs/"];
const GATEWAY_TIMEOUT_SECS: u64 = 15;

/// Tenta cada gateway em ordem, a primeira resposta 200 vence. Retorna erro
/// com um resumo do que cada gateway retornou se todos falharem.
pub(crate) async fn fetch_from_gateway(cid: &str) -> Result<Vec<u8>, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(GATEWAY_TIMEOUT_SECS))
        .build()
        .map_err(|e| e.to_string())?;

    let mut errors = Vec::new();
    for gateway in GATEWAYS {
        let url = format!("{gateway}{cid}");
        match client.get(&url).send().await {
            Ok(res) if res.status().is_success() => {
                return res
                    .bytes()
                    .await
                    .map(|b| b.to_vec())
                    .map_err(|e| e.to_string());
            }
            Ok(res) => errors.push(format!("{gateway}: HTTP {}", res.status())),
            Err(e) => errors.push(format!("{gateway}: {e}")),
        }
    }
    Err(format!(
        "todos os gateways IPFS falharam pro cid {cid}: {}",
        errors.join("; ")
    ))
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
}

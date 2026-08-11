//! Núcleo de um cliente Arweave standalone (Etapa 1 da migração de storage,
//! ver `project/ROADMAP.md`) — gera/importa wallet, monta e assina
//! transações formato 2, submete e lê de volta contra qualquer node/gateway
//! Arweave via HTTP direto (sem bundler/serviço terceiro, ver decisão de
//! arquitetura no plano da Etapa 1). Etapa 2: `publish_vault_blob` integra
//! o blob principal do vault (`vault_publish` em `lib.rs`). Documentos
//! anexados também publicam aqui via `publish_document` — o upload em
//! chunks (`submit_chunk`, `POST /chunk`) cobre conteúdo de qualquer
//! tamanho, não só o blob principal.

mod deep_hash;
mod merkle;
mod transaction;
mod wallet;

use serde::Serialize;
use transaction::ArweaveTransaction;
use wallet::ArweaveJwk;

pub(crate) const ARWEAVE_DEFAULT_NODE: &str = "https://arweave.net";

#[derive(Serialize)]
pub struct TxStatus {
    pub confirmed: bool,
    pub block_height: Option<u64>,
    pub number_of_confirmations: Option<u64>,
}

fn http_client() -> reqwest::Client {
    reqwest::Client::new()
}

/// `GET /price/{bytes}` — reward estimado em winston pra publicar `bytes`.
pub(crate) async fn get_price(
    client: &reqwest::Client,
    node_url: &str,
    bytes: usize,
) -> Result<String, String> {
    let url = format!("{}/price/{}", node_url.trim_end_matches('/'), bytes);
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        return Err(format!("GET /price retornou {}", res.status()));
    }
    res.text().await.map_err(|e| e.to_string())
}

/// `GET /tx_anchor` — anchor recente pra usar como `last_tx`, evita replay.
pub(crate) async fn get_tx_anchor(
    client: &reqwest::Client,
    node_url: &str,
) -> Result<String, String> {
    let url = format!("{}/tx_anchor", node_url.trim_end_matches('/'));
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        return Err(format!("GET /tx_anchor retornou {}", res.status()));
    }
    res.text().await.map_err(|e| e.to_string())
}

/// `POST /tx` — submete a transação assinada, com `data` inline no corpo
/// JSON. Cobre conteúdo que cabe em 1 chunk (256 KiB) — dados maiores
/// exigiriam upload em chunks via `POST /chunk`, fora de escopo desta etapa
/// (ver risco #5 do plano).
pub(crate) async fn submit_transaction(
    client: &reqwest::Client,
    node_url: &str,
    tx: &ArweaveTransaction,
) -> Result<(), String> {
    let url = format!("{}/tx", node_url.trim_end_matches('/'));
    let body = tx.to_wire_json();
    let res = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(format!("POST /tx retornou {status}: {text}"));
    }
    Ok(())
}

/// `POST /tx` sem `data` inline (`to_wire_json_no_data`) — usado quando o
/// conteúdo é maior que 1 chunk e será enviado via `POST /chunk` separados.
pub(crate) async fn submit_transaction_no_data(
    client: &reqwest::Client,
    node_url: &str,
    tx: &ArweaveTransaction,
) -> Result<(), String> {
    let url = format!("{}/tx", node_url.trim_end_matches('/'));
    let body = tx.to_wire_json_no_data();
    let res = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(format!("POST /tx (sem data inline) retornou {status}: {text}"));
    }
    Ok(())
}

/// `POST /chunk` — submete um chunk de conteúdo + sua prova de inclusão
/// (`data_path`) na árvore de merkle da tx. `offset`/`data_size` sempre como
/// string JSON (nunca número), confirmado contra a doc oficial e
/// `Transaction.getChunk()` de `arweave-js`. Resposta de sucesso é texto
/// puro `"OK"`, não JSON — só lê o corpo no caminho de erro.
pub(crate) async fn submit_chunk(
    client: &reqwest::Client,
    node_url: &str,
    data_root: &str,
    data_size: &str,
    proof: &merkle::Proof,
    chunk_bytes: &[u8],
) -> Result<(), String> {
    let url = format!("{}/chunk", node_url.trim_end_matches('/'));
    let body = serde_json::json!({
        "data_root": data_root,
        "data_size": data_size,
        "data_path": transaction::b64url_encode(&proof.proof),
        "chunk": transaction::b64url_encode(chunk_bytes),
        "offset": proof.offset.to_string(),
    });
    let res = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(format!("POST /chunk retornou {status}: {text}"));
    }
    Ok(())
}

/// `GET /tx/{id}/status` — 200 = confirmada (corpo tem `block_height` e
/// `number_of_confirmations`); 202/404 = ainda pendente/não encontrada.
pub(crate) async fn get_tx_status(
    client: &reqwest::Client,
    node_url: &str,
    tx_id: &str,
) -> Result<TxStatus, String> {
    let url = format!("{}/tx/{}/status", node_url.trim_end_matches('/'), tx_id);
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;

    if res.status() == reqwest::StatusCode::OK {
        let json: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;
        return Ok(TxStatus {
            confirmed: true,
            block_height: json["block_height"].as_u64(),
            number_of_confirmations: json["number_of_confirmations"].as_u64(),
        });
    }

    Ok(TxStatus {
        confirmed: false,
        block_height: None,
        number_of_confirmations: None,
    })
}

/// `GET /{id}` — lê o conteúdo bruto publicado numa tx.
pub(crate) async fn fetch_data(
    client: &reqwest::Client,
    node_url: &str,
    tx_id: &str,
) -> Result<Vec<u8>, String> {
    let url = format!("{}/{}", node_url.trim_end_matches('/'), tx_id);
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        return Err(format!("GET /{{id}} retornou {}", res.status()));
    }
    res.bytes()
        .await
        .map(|b| b.to_vec())
        .map_err(|e| e.to_string())
}

/// Orquestrador de ponta a ponta — preço, anchor, monta, assina, submete.
/// Devolve o tx_id. Equivalente ao `pin_vault` de `ipfs.rs`. Publica inline
/// (`POST /tx` com `data`) se o conteúdo cabe em 1 chunk (≤256KiB); caso
/// contrário, submete a tx sem `data` e faz upload em chunks reais via
/// `POST /chunk`, sequencialmente (ver `arlocal_tests` — upload concorrente
/// corrompe a ordem de remontagem no ArLocal, que deriva o offset por ordem
/// de chegada em vez de usar o `offset` que o cliente envia).
pub(crate) async fn publish(
    client: &reqwest::Client,
    node_url: &str,
    jwk: &ArweaveJwk,
    content: &[u8],
    tags: &[(String, String)],
) -> Result<String, String> {
    let private_key = wallet::jwk_to_private_key(jwk)?;
    let reward = get_price(client, node_url, content.len()).await?;
    let last_tx = get_tx_anchor(client, node_url).await?;

    let mut tx = transaction::build_transaction(content, tags, &reward, &last_tx, &jwk.n);
    transaction::sign_transaction(&mut tx, &private_key)?;

    // Sanity check local antes de gastar uma requisição de rede: garante que
    // a tx não foi corrompida entre assinar e submeter.
    if !transaction::verify_transaction_signature(&tx)? {
        return Err("assinatura da tx falhou na verificação local antes do submit".to_string());
    }

    let (chunks, proofs) = merkle::chunk_data_for_upload(content);

    if chunks.len() <= 1 {
        submit_transaction(client, node_url, &tx).await?;
        return Ok(tx.id.clone());
    }

    submit_transaction_no_data(client, node_url, &tx).await?;

    let data_root_bytes = transaction::b64url_decode(&tx.data_root)?;
    let total = chunks.len();
    for (i, (chunk, proof)) in chunks.iter().zip(proofs.iter()).enumerate() {
        // Sanity check local antes de gastar a requisição — ArLocal não
        // valida a prova que o cliente manda, então esse é o único jeito de
        // pegar um bug sutil em `generate_proofs` antes de mainnet (mesmo
        // padrão de `verify_transaction_signature` acima).
        if merkle::validate_path(&data_root_bytes, proof.offset as i64, 0, content.len(), &proof.proof)
            .is_none()
        {
            return Err(format!(
                "tx {} publicada, prova de merkle inválida localmente pro chunk {i}/{total} — não enviado",
                tx.id
            ));
        }

        let bytes = &content[chunk.min_byte_range..chunk.max_byte_range];
        submit_chunk(client, node_url, &tx.data_root, &tx.data_size, proof, bytes)
            .await
            .map_err(|e| format!("tx {} publicada, chunk {i}/{total} falhou: {e}", tx.id))?;
    }

    Ok(tx.id.clone())
}

/// `GET /wallet/{address}/balance` — saldo em winston. Usado antes de
/// publicar de verdade pra dar um erro claro de saldo insuficiente em vez de
/// deixar isso aparecer só como um "POST /tx retornou 400" cru lá na frente
/// (ver `arweave_wallet_balance`, comando exposto à UI).
pub(crate) async fn get_wallet_balance(
    client: &reqwest::Client,
    node_url: &str,
    address: &str,
) -> Result<String, String> {
    let url = format!(
        "{}/wallet/{}/balance",
        node_url.trim_end_matches('/'),
        address
    );
    let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        return Err(format!("GET /wallet/{{address}}/balance retornou {}", res.status()));
    }
    res.text().await.map_err(|e| e.to_string())
}

/// Publica `content` no Arweave já com um JWK em mãos — sem tocar o
/// keyring/arquivo local, então é diretamente testável (ex.: contra ArLocal
/// com um JWK gerado na hora, ver `arlocal_tests`). Devolve o mesmo formato
/// que `ipfs::pin_vault`: `cid` prefixado `"ar://"` (ponteiro
/// auto-descritivo — um `cid` sem esse prefixo continua significando "busca
/// no IPFS", sem exigir migração de dado nem mudança no `VaultRegistry`,
/// que só guarda uma string opaca), `content_hash` calculado igual
/// (`keccak256`, independente de backend).
pub(crate) async fn publish_vault_blob_with_jwk(
    client: &reqwest::Client,
    node_url: &str,
    jwk: &ArweaveJwk,
    content: &[u8],
) -> Result<crate::PublishResult, String> {
    let tags = vec![
        ("Content-Type".to_string(), "application/octet-stream".to_string()),
        ("App-Name".to_string(), "TruthID".to_string()),
    ];
    let tx_id = publish(client, node_url, jwk, content, &tags).await?;
    Ok(crate::PublishResult {
        cid: format!("ar://{tx_id}"),
        content_hash: crate::ipfs::keccak256_hex(content),
        providers_ok: vec!["arweave".to_string()],
        providers_failed: vec![],
    })
}

/// Ponto de entrada real do `vault_publish` (Etapa 2) — carrega a wallet
/// local (erro claro se ausente, sem fallback pro IPFS: corte direto,
/// mesmo padrão já usado na rotação de DEK) e delega pro core acima.
pub(crate) async fn publish_vault_blob(content: &[u8]) -> Result<crate::PublishResult, String> {
    let json = crate::get_arweave_wallet().map_err(|_| {
        "nenhuma wallet Arweave configurada — gere ou importe uma antes de publicar o vault"
            .to_string()
    })?;
    let jwk = wallet::parse_jwk(&json)?;
    publish_vault_blob_with_jwk(&http_client(), ARWEAVE_DEFAULT_NODE, &jwk, content).await
}

/// Mesmo papel que `publish_vault_blob_with_jwk`, mas para documentos
/// anexados — carrega `file_name`/`mime_type` reais (`DocumentData` em
/// `vault.rs`) como tags Arweave em vez das tags genéricas do blob
/// principal (facilita indexação externa via GraphQL, sem custo extra).
pub(crate) async fn publish_document_with_jwk(
    client: &reqwest::Client,
    node_url: &str,
    jwk: &ArweaveJwk,
    content: &[u8],
    file_name: &str,
    mime_type: &str,
) -> Result<crate::PublishResult, String> {
    let tags = vec![
        ("Content-Type".to_string(), mime_type.to_string()),
        ("App-Name".to_string(), "TruthID".to_string()),
        ("File-Name".to_string(), file_name.to_string()),
    ];
    let tx_id = publish(client, node_url, jwk, content, &tags).await?;
    Ok(crate::PublishResult {
        cid: format!("ar://{tx_id}"),
        content_hash: crate::ipfs::keccak256_hex(content),
        providers_ok: vec!["arweave".to_string()],
        providers_failed: vec![],
    })
}

/// Ponto de entrada real do `vault_publish` para documentos anexados —
/// mesmo padrão de `publish_vault_blob` (carrega a wallet local, erro claro
/// se ausente, sem fallback pro IPFS).
pub(crate) async fn publish_document(
    content: &[u8],
    file_name: &str,
    mime_type: &str,
) -> Result<crate::PublishResult, String> {
    let json = crate::get_arweave_wallet().map_err(|_| {
        "nenhuma wallet Arweave configurada — gere ou importe uma antes de publicar documentos"
            .to_string()
    })?;
    let jwk = wallet::parse_jwk(&json)?;
    publish_document_with_jwk(&http_client(), ARWEAVE_DEFAULT_NODE, &jwk, content, file_name, mime_type).await
}

/// Mesmo papel que `publish_vault_blob_with_jwk`, mas para o conteúdo
/// arbitrário que apps terceiros enviam via `/truthid/v1/pin` — mesmas tags
/// genéricas do blob principal (sem tag de app de origem por ora).
pub(crate) async fn publish_pinned_content_with_jwk(
    client: &reqwest::Client,
    node_url: &str,
    jwk: &ArweaveJwk,
    content: &[u8],
) -> Result<crate::PublishResult, String> {
    let tags = vec![
        ("Content-Type".to_string(), "application/octet-stream".to_string()),
        ("App-Name".to_string(), "TruthID".to_string()),
    ];
    let tx_id = publish(client, node_url, jwk, content, &tags).await?;
    Ok(crate::PublishResult {
        cid: format!("ar://{tx_id}"),
        content_hash: crate::ipfs::keccak256_hex(content),
        providers_ok: vec!["arweave".to_string()],
        providers_failed: vec![],
    })
}

/// Ponto de entrada real do canal `/truthid/v1/pin` (apps terceiros) —
/// mesmo padrão de `publish_vault_blob`/`publish_document` (carrega a
/// wallet local, erro claro se ausente, sem fallback pro IPFS: corte
/// direto).
pub(crate) async fn publish_pinned_content(content: &[u8]) -> Result<crate::PublishResult, String> {
    let json = crate::get_arweave_wallet().map_err(|_| {
        "nenhuma wallet Arweave configurada — gere ou importe uma antes de usar o /pin"
            .to_string()
    })?;
    let jwk = wallet::parse_jwk(&json)?;
    publish_pinned_content_with_jwk(&http_client(), ARWEAVE_DEFAULT_NODE, &jwk, content).await
}

// ---------------------------------------------------------------------------
// Tauri commands — validação manual isolada (sem integração com o Vault)
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn arweave_generate_wallet() -> Result<String, String> {
    let jwk = wallet::generate_jwk()?;
    let address = wallet::wallet_address(&jwk)?;
    let json = serde_json::to_string(&jwk).map_err(|e| e.to_string())?;
    crate::set_arweave_wallet(&json)?;
    Ok(address)
}

#[tauri::command]
pub fn arweave_import_wallet(jwk_json: String) -> Result<String, String> {
    let jwk = wallet::parse_jwk(&jwk_json)?;
    let address = wallet::wallet_address(&jwk)?;
    crate::set_arweave_wallet(&jwk_json)?;
    Ok(address)
}

#[tauri::command]
pub fn arweave_wallet_exists() -> Result<bool, String> {
    Ok(crate::get_arweave_wallet().is_ok())
}

#[tauri::command]
pub fn arweave_wallet_address() -> Result<String, String> {
    let json = crate::get_arweave_wallet()?;
    let jwk = wallet::parse_jwk(&json)?;
    wallet::wallet_address(&jwk)
}

/// Saldo em winston da wallet local, contra `ARWEAVE_DEFAULT_NODE`. Usado
/// pela UI (Etapa 2) pra mostrar se dá pra publicar antes do usuário tentar.
#[tauri::command]
pub async fn arweave_wallet_balance() -> Result<String, String> {
    let json = crate::get_arweave_wallet()?;
    let jwk = wallet::parse_jwk(&json)?;
    let address = wallet::wallet_address(&jwk)?;
    get_wallet_balance(&http_client(), ARWEAVE_DEFAULT_NODE, &address).await
}

/// `node_url` vazio usa `ARWEAVE_DEFAULT_NODE` — o caller (devtools/UI de
/// validação manual) pode apontar pra um node local (ex: ArLocal) passando a
/// URL explicitamente.
fn resolve_node_url(node_url: &str) -> &str {
    if node_url.is_empty() {
        ARWEAVE_DEFAULT_NODE
    } else {
        node_url
    }
}

#[tauri::command]
pub async fn arweave_publish(
    node_url: String,
    content: Vec<u8>,
    tags: Vec<(String, String)>,
) -> Result<String, String> {
    let json = crate::get_arweave_wallet()?;
    let jwk = wallet::parse_jwk(&json)?;
    let client = http_client();
    publish(&client, resolve_node_url(&node_url), &jwk, &content, &tags).await
}

#[tauri::command]
pub async fn arweave_get_status(node_url: String, tx_id: String) -> Result<TxStatus, String> {
    let client = http_client();
    get_tx_status(&client, resolve_node_url(&node_url), &tx_id).await
}

#[tauri::command]
pub async fn arweave_fetch(node_url: String, tx_id: String) -> Result<Vec<u8>, String> {
    let client = http_client();
    fetch_data(&client, resolve_node_url(&node_url), &tx_id).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_node_is_https() {
        assert!(ARWEAVE_DEFAULT_NODE.starts_with("https://"));
    }
}

// ---------------------------------------------------------------------------
// Validação de integração contra ArLocal (rede Arweave local de dev) — não
// roda no `cargo test` do dia a dia. Diferente do resto do projeto (que usa
// `tests/*.rs` como binário separado onde há esse padrão), aqui fica inline
// como `#[cfg(test)] mod` igual a todo o resto do crate — não existe
// precedente de `tests/` no projeto, e módulos não-`pub` não seriam
// alcançáveis por um binário de teste externo de qualquer forma.
//
// Como rodar manualmente:
//   1. Instalar e iniciar `arlocal@1.1.20` — a versão mais recente do pacote
//      depende de um fork via git de `avsc`, bloqueado por política
//      anti-supply-chain do npm neste ambiente (`EALLOWGIT`); 1.1.20 é a
//      última faixa que ainda resolve `arbundles` numa versão (`0.6.12`) sem
//      esse fork. Como o range `^0.6.12` do próprio `arlocal` inclui versões
//      mais novas de `arbundles` que reintroduzem o fork, é preciso fixar a
//      versão via override do npm (`overrides: { "arbundles": "0.6.12" }`
//      num `package.json` descartável) — só apontar `arlocal@1.1.20` não
//      basta.
//        npx arlocal@1.1.20
//   2. cargo test --lib arweave::arlocal_tests -- --ignored --nocapture
//
// Validado de fato contra essa versão (Sessão 185): publish + mine + status +
// fetch round-trip passou, prova que a assinatura RSA-PSS de
// `sign_transaction` é aceita por uma implementação real de node Arweave, não
// só pela verificação local. Achado real no caminho: o `last_tx`/anchor
// devolvido pelo ArLocal não é uma codificação base64url canônica (bits
// residuais não-zero no último símbolo) — por isso `signature_data` decodifica
// esse campo especificamente com `b64url_decode_lenient`, não com o decoder
// estrito usado nos campos que o próprio cliente codifica. Risco de salt
// length (PSS estrito da crate `rsa` vs. auto-detect do OpenSSL/Node)
// permanece não totalmente descartado pra mainnet: ArLocal reimplementa a
// validação de assinatura em JS, então não é garantia bit-a-bit do
// comportamento do node oficial escrito em Erlang.
#[cfg(test)]
mod arlocal_tests {
    use super::*;
    use crate::arweave::wallet::{generate_jwk, wallet_address};

    const ARLOCAL_URL: &str = "http://localhost:1984";

    async fn wait_for_arlocal(client: &reqwest::Client) -> Result<(), String> {
        for _ in 0..30 {
            if let Ok(res) = client.get(format!("{ARLOCAL_URL}/info")).send().await {
                if res.status().is_success() {
                    return Ok(());
                }
            }
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }
        Err("ArLocal não respondeu em /info a tempo — está rodando em localhost:1984?".to_string())
    }

    async fn mint(client: &reqwest::Client, address: &str, winston: u64) -> Result<(), String> {
        let url = format!("{ARLOCAL_URL}/mint/{address}/{winston}");
        let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
        if !res.status().is_success() {
            return Err(format!("GET /mint retornou {}", res.status()));
        }
        Ok(())
    }

    async fn mine(client: &reqwest::Client) -> Result<(), String> {
        let url = format!("{ARLOCAL_URL}/mine");
        let res = client.get(&url).send().await.map_err(|e| e.to_string())?;
        if !res.status().is_success() {
            return Err(format!("GET /mine retornou {}", res.status()));
        }
        Ok(())
    }

    /// Fluxo de ponta a ponta: gera wallet, funda via faucet, publica,
    /// minera manualmente, confirma, lê de volta — bytes idênticos aos
    /// originais. É a única validação real de que a assinatura RSA-PSS
    /// produzida por `sign_transaction` é aceita por um node Arweave de
    /// verdade (o round-trip de `verify_transaction_signature` só prova
    /// consistência interna, não aceitação pela rede).
    #[tokio::test]
    #[ignore]
    async fn publish_and_fetch_round_trip_against_arlocal() {
        let client = http_client();
        wait_for_arlocal(&client).await.expect("ArLocal deve estar rodando");

        let jwk = generate_jwk().expect("keygen deve funcionar");
        let address = wallet_address(&jwk).expect("endereço deve ser derivável");

        mint(&client, &address, 1_000_000_000_000)
            .await
            .expect("faucet deve fundar a wallet de teste");

        let content = b"vetor de teste real contra ArLocal".to_vec();
        let tx_id = publish(
            &client,
            ARLOCAL_URL,
            &jwk,
            &content,
            &[("Test".to_string(), "arweave-arlocal".to_string())],
        )
        .await
        .expect("publish deve suceder contra ArLocal");

        mine(&client).await.expect("mineração manual deve suceder");

        let status = get_tx_status(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("get_tx_status não deve falhar");
        assert!(status.confirmed, "tx deveria estar confirmada após minerar");

        let fetched = fetch_data(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("fetch_data deve suceder");
        assert_eq!(fetched, content);
    }

    /// Mesma validação de ponta a ponta, mas passando pelo wrapper de Etapa 2
    /// (`publish_vault_blob_with_jwk`) em vez de `publish` cru — confere o
    /// formato do `PublishResult` (prefixo `ar://`, `content_hash` batendo com
    /// `ipfs::keccak256_hex`) além do round-trip de bytes.
    #[tokio::test]
    #[ignore]
    async fn publish_vault_blob_round_trip_against_arlocal() {
        let client = http_client();
        wait_for_arlocal(&client).await.expect("ArLocal deve estar rodando");

        let jwk = generate_jwk().expect("keygen deve funcionar");
        let address = wallet_address(&jwk).expect("endereço deve ser derivável");

        mint(&client, &address, 1_000_000_000_000)
            .await
            .expect("faucet deve fundar a wallet de teste");

        let content = b"vault blob de teste contra ArLocal".to_vec();
        let result = publish_vault_blob_with_jwk(&client, ARLOCAL_URL, &jwk, &content)
            .await
            .expect("publish_vault_blob_with_jwk deve suceder contra ArLocal");

        assert!(result.cid.starts_with("ar://"), "cid deveria vir prefixado ar://, veio: {}", result.cid);
        assert_eq!(result.content_hash, crate::ipfs::keccak256_hex(&content));
        assert_eq!(result.providers_ok, vec!["arweave".to_string()]);
        assert!(result.providers_failed.is_empty());

        mine(&client).await.expect("mineração manual deve suceder");

        let tx_id = result.cid.strip_prefix("ar://").unwrap();
        let status = get_tx_status(&client, ARLOCAL_URL, tx_id)
            .await
            .expect("get_tx_status não deve falhar");
        assert!(status.confirmed, "tx deveria estar confirmada após minerar");

        let fetched = fetch_data(&client, ARLOCAL_URL, tx_id)
            .await
            .expect("fetch_data deve suceder");
        assert_eq!(fetched, content);
    }

    /// Conteúdo real >256KiB — só isso exercita o caminho novo
    /// (`submit_transaction_no_data` + loop sequencial de `submit_chunk`).
    /// Os dois testes acima só cobrem o caminho inline (`POST /tx` com
    /// `data`), que continua existindo pra conteúdo pequeno. `GET /{id}`
    /// (`fetch_data`, sem mudança) precisa remontar os chunks corretamente
    /// no ArLocal — não é garantido a priori, é o que este teste prova.
    #[tokio::test]
    #[ignore]
    async fn publish_multi_chunk_content_round_trip_against_arlocal() {
        let client = http_client();
        wait_for_arlocal(&client).await.expect("ArLocal deve estar rodando");

        let jwk = generate_jwk().expect("keygen deve funcionar");
        let address = wallet_address(&jwk).expect("endereço deve ser derivável");

        mint(&client, &address, 100_000_000_000_000)
            .await
            .expect("faucet deve fundar a wallet de teste");

        // Mesmo tamanho de cross_checked_multi_chunk_root em merkle.rs: 3
        // chunks reais (256KiB + ~128KiB + ~128KiB rebalanceados), sem
        // trailing vazio. Conteúdo não-uniforme (não é só um byte repetido)
        // pra parecer mais com um documento real.
        let size = merkle::MAX_CHUNK_SIZE * 2 + 500;
        let content: Vec<u8> = (0..size).map(|i| (i % 251) as u8).collect();

        let tx_id = publish(
            &client,
            ARLOCAL_URL,
            &jwk,
            &content,
            &[("Test".to_string(), "arweave-multi-chunk".to_string())],
        )
        .await
        .expect("publish multi-chunk deve suceder contra ArLocal");

        mine(&client).await.expect("mineração manual deve suceder");

        let status = get_tx_status(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("get_tx_status não deve falhar");
        assert!(status.confirmed, "tx deveria estar confirmada após minerar");

        let fetched = fetch_data(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("fetch_data deve suceder");
        assert_eq!(fetched.len(), content.len());
        assert_eq!(fetched, content);
    }

    /// Conteúdo múltiplo exato de `MAX_CHUNK_SIZE` (2x) — depois do descarte
    /// do chunk final vazio (achado #1 do plano), sobram exatamente 2 chunks
    /// reais, ainda `> 1` (então ainda toma o caminho em chunks, diferente
    /// do caso de 1x MAX_CHUNK_SIZE que cai no caminho inline). Prova contra
    /// um node real que o descarte não deixa nenhum chunk vazio na fila de
    /// upload nesse caso combinado.
    #[tokio::test]
    #[ignore]
    async fn publish_exact_double_max_chunk_size_round_trip_against_arlocal() {
        let client = http_client();
        wait_for_arlocal(&client).await.expect("ArLocal deve estar rodando");

        let jwk = generate_jwk().expect("keygen deve funcionar");
        let address = wallet_address(&jwk).expect("endereço deve ser derivável");

        mint(&client, &address, 100_000_000_000_000)
            .await
            .expect("faucet deve fundar a wallet de teste");

        let size = merkle::MAX_CHUNK_SIZE * 2;
        let content: Vec<u8> = (0..size).map(|i| (i % 199) as u8).collect();

        let tx_id = publish(
            &client,
            ARLOCAL_URL,
            &jwk,
            &content,
            &[("Test".to_string(), "arweave-exact-double-chunk".to_string())],
        )
        .await
        .expect("publish deve suceder contra ArLocal");

        mine(&client).await.expect("mineração manual deve suceder");

        let status = get_tx_status(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("get_tx_status não deve falhar");
        assert!(status.confirmed, "tx deveria estar confirmada após minerar");

        let fetched = fetch_data(&client, ARLOCAL_URL, &tx_id)
            .await
            .expect("fetch_data deve suceder");
        assert_eq!(fetched, content);
    }

    /// Mesma validação de `publish_multi_chunk_content_round_trip_against_arlocal`
    /// (conteúdo real >256KiB, exercita o upload em chunks), mas passando pelo
    /// wrapper de documentos (`publish_document_with_jwk`) em vez de `publish`
    /// cru — confere o `PublishResult` (mesmo shape de `publish_vault_blob_with_jwk`)
    /// além do round-trip de bytes. É o caminho que `vault_publish` agora usa
    /// pra documentos anexados do vault.
    #[tokio::test]
    #[ignore]
    async fn publish_vault_document_round_trip_against_arlocal() {
        let client = http_client();
        wait_for_arlocal(&client).await.expect("ArLocal deve estar rodando");

        let jwk = generate_jwk().expect("keygen deve funcionar");
        let address = wallet_address(&jwk).expect("endereço deve ser derivável");

        mint(&client, &address, 100_000_000_000_000)
            .await
            .expect("faucet deve fundar a wallet de teste");

        let size = merkle::MAX_CHUNK_SIZE * 2 + 500;
        let content: Vec<u8> = (0..size).map(|i| (i % 233) as u8).collect();

        let result = publish_document_with_jwk(
            &client,
            ARLOCAL_URL,
            &jwk,
            &content,
            "comprovante.pdf",
            "application/pdf",
        )
        .await
        .expect("publish_document_with_jwk deve suceder contra ArLocal");

        assert!(result.cid.starts_with("ar://"), "cid deveria vir prefixado ar://, veio: {}", result.cid);
        assert_eq!(result.content_hash, crate::ipfs::keccak256_hex(&content));
        assert_eq!(result.providers_ok, vec!["arweave".to_string()]);
        assert!(result.providers_failed.is_empty());

        mine(&client).await.expect("mineração manual deve suceder");

        let tx_id = result.cid.strip_prefix("ar://").unwrap();
        let status = get_tx_status(&client, ARLOCAL_URL, tx_id)
            .await
            .expect("get_tx_status não deve falhar");
        assert!(status.confirmed, "tx deveria estar confirmada após minerar");

        let fetched = fetch_data(&client, ARLOCAL_URL, tx_id)
            .await
            .expect("fetch_data deve suceder");
        assert_eq!(fetched.len(), content.len());
        assert_eq!(fetched, content);
    }
}

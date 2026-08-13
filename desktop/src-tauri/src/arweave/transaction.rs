use crate::arweave::deep_hash::{deep_hash, DeepHashChunk};
use crate::arweave::merkle::{chunk_data, compute_data_root};
use rsa::pss::{Signature, SigningKey, VerifyingKey};
use rsa::signature::{RandomizedSigner, SignatureEncoding, Verifier};
use rsa::{BigUint, RsaPrivateKey, RsaPublicKey};
use sha2::{Digest, Sha256};

pub(crate) fn b64url_encode(bytes: &[u8]) -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    URL_SAFE_NO_PAD.encode(bytes)
}

pub(crate) fn b64url_decode(s: &str) -> Result<Vec<u8>, String> {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    URL_SAFE_NO_PAD.decode(s).map_err(|e| e.to_string())
}

/// Decodifica campos que vêm de fora (ex.: `last_tx`/anchor, respondido pelo
/// node) de forma permissiva quanto a bits residuais no último símbolo.
/// Diferente de `b64url_decode` (usado nos campos que nós mesmos codificamos,
/// onde qualquer desvio indica bug real), aqui a origem é opaca — um anchor
/// tecnicamente só precisa ser um blob base64url válido nos *caracteres*, não
/// necessariamente canônico bit-a-bit. Achado validando contra ArLocal: o
/// anchor que ele gera usa alfabeto base64url válido mas não é uma codificação
/// canônica (bits residuais != 0), o que o decoder estrito rejeita.
fn b64url_decode_lenient(s: &str) -> Result<Vec<u8>, String> {
    use base64::{
        alphabet,
        engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig},
        Engine as _,
    };
    let engine = GeneralPurpose::new(
        &alphabet::URL_SAFE,
        GeneralPurposeConfig::new()
            .with_encode_padding(false)
            .with_decode_padding_mode(DecodePaddingMode::Indifferent)
            .with_decode_allow_trailing_bits(true),
    );
    engine.decode(s).map_err(|e| e.to_string())
}

/// Transação Arweave formato 2. Espelha `Transaction` de `arweave-js`
/// (`lib/transaction.ts`) — mesmos nomes de campo, mesmo encoding
/// (base64url sem padding pra tudo exceto `data`, que fica em bytes crus até
/// a serialização final pro `POST /tx`).
pub(crate) struct ArweaveTransaction {
    pub format: u8,
    pub id: String,
    pub last_tx: String,
    pub owner: String,
    /// Nome/valor em texto puro (UTF-8) — só vira base64url na fronteira de
    /// serialização JSON (`mod.rs`), não aqui.
    pub tags: Vec<(String, String)>,
    pub target: String,
    pub quantity: String,
    pub data_root: String,
    pub data_size: String,
    pub data: Vec<u8>,
    pub reward: String,
    pub signature: String,
}

/// Monta a tx com `target`/`quantity` fixos (upload puro, sem transferência
/// de valor — fora de escopo desta etapa) e calcula `data_root`. Ainda não
/// assinada (`id`/`signature` vazios) — chamar `sign_transaction` em seguida.
///
/// Replica o caso especial de `arweave-js` `prepareChunks`: dado vazio usa
/// `data_root = ""` (string vazia, não o hash de um chunk vazio) — evita
/// computar merkle sobre "nada" só pra descartar depois.
pub(crate) fn build_transaction(
    data: &[u8],
    tags: &[(String, String)],
    reward: &str,
    last_tx: &str,
    owner_n_b64: &str,
) -> ArweaveTransaction {
    let data_root = if data.is_empty() {
        String::new()
    } else {
        b64url_encode(&compute_data_root(&chunk_data(data)))
    };

    ArweaveTransaction {
        format: 2,
        id: String::new(),
        last_tx: last_tx.to_string(),
        owner: owner_n_b64.to_string(),
        tags: tags.to_vec(),
        target: String::new(),
        quantity: "0".to_string(),
        data_root,
        data_size: data.len().to_string(),
        data: data.to_vec(),
        reward: reward.to_string(),
        signature: String::new(),
    }
}

/// Monta a entrada do deep hash (formato 2) exatamente como
/// `Transaction.getSignatureData()` em `arweave-js`: format, owner, target,
/// quantity, reward, last_tx, tags (lista de pares [nome, valor] em bytes
/// crus), data_size, data_root — nessa ordem.
fn signature_data(tx: &ArweaveTransaction) -> Result<[u8; 48], String> {
    let owner_bytes = b64url_decode(&tx.owner)?;
    let target_bytes = b64url_decode(&tx.target)?;
    let last_tx_bytes = b64url_decode_lenient(&tx.last_tx)?;
    let data_root_bytes = b64url_decode(&tx.data_root)?;

    let tag_list = DeepHashChunk::List(
        tx.tags
            .iter()
            .map(|(name, value)| {
                DeepHashChunk::List(vec![DeepHashChunk::utf8(name), DeepHashChunk::utf8(value)])
            })
            .collect(),
    );

    let chunk = DeepHashChunk::List(vec![
        DeepHashChunk::utf8(&tx.format.to_string()),
        DeepHashChunk::blob(owner_bytes),
        DeepHashChunk::blob(target_bytes),
        DeepHashChunk::utf8(&tx.quantity),
        DeepHashChunk::utf8(&tx.reward),
        DeepHashChunk::blob(last_tx_bytes),
        tag_list,
        DeepHashChunk::utf8(&tx.data_size),
        DeepHashChunk::blob(data_root_bytes),
    ]);
    Ok(deep_hash(&chunk))
}

/// Assina a tx: RSA-PSS/SHA-256 sobre o deep hash dos campos. Preenche
/// `signature` e `id` (`id = SHA-256(signature)`, base64url). PSS usa salt
/// aleatório por assinatura (via `SigningKey<Sha256>`, salt = tamanho do
/// digest, 32 bytes) — duas assinaturas da mesma tx nunca são bit-a-bit
/// iguais, só ambas válidas. A aceitação por um node Arweave real (que pode
/// ter sido assinado historicamente com salt maior, ex. Node.js/OpenSSL
/// `RSA_PSS_SALTLEN_MAX_SIGN` por padrão) depende de o verificador do node
/// seguir RFC 8017 (salt auto-derivado do padding, não fixo) — validado de
/// fato só contra ArLocal/mainnet, não é garantido só por este código.
pub(crate) fn sign_transaction(
    tx: &mut ArweaveTransaction,
    private_key: &RsaPrivateKey,
) -> Result<(), String> {
    let sig_data = signature_data(tx)?;
    let mut rng = rand::thread_rng();
    let signing_key = SigningKey::<Sha256>::new(private_key.clone());
    let signature = signing_key.sign_with_rng(&mut rng, &sig_data);
    let sig_bytes = signature.to_bytes().to_vec();
    let id_digest = Sha256::digest(&sig_bytes);

    tx.signature = b64url_encode(&sig_bytes);
    tx.id = b64url_encode(&id_digest);
    Ok(())
}

/// Verificação local (RSA-PSS/SHA-256 contra o próprio deep hash) — só
/// garante consistência interna (a tx não foi corrompida entre assinar e
/// submeter), não confirma nada contra a rede real. `e_b64` precisa ser o
/// expoente público *real* da wallet (`ArweaveJwk::e`) — wallets importadas
/// podem ter um expoente diferente de 65537 (o padrão que só `generate_jwk`
/// usa pra chaves novas), então não pode ser assumido aqui.
pub(crate) fn verify_transaction_signature(
    tx: &ArweaveTransaction,
    e_b64: &str,
) -> Result<bool, String> {
    let sig_data = signature_data(tx)?;
    let n = BigUint::from_bytes_be(&b64url_decode(&tx.owner)?);
    let e = BigUint::from_bytes_be(&b64url_decode(e_b64)?);
    let pub_key = RsaPublicKey::new(n, e).map_err(|e| e.to_string())?;
    let verifying_key = VerifyingKey::<Sha256>::new(pub_key);

    let sig_bytes = b64url_decode(&tx.signature)?;
    let sig = Signature::try_from(sig_bytes.as_slice()).map_err(|e| e.to_string())?;
    Ok(verifying_key.verify(&sig_data, &sig).is_ok())
}

impl ArweaveTransaction {
    /// Corpo JSON compartilhado por `to_wire_json`/`to_wire_json_no_data` —
    /// só o campo `data` muda entre as duas variantes, o resto é idêntico.
    fn to_wire_json_impl(&self, data_b64: String) -> serde_json::Value {
        let tags: Vec<serde_json::Value> = self
            .tags
            .iter()
            .map(|(name, value)| {
                serde_json::json!({
                    "name": b64url_encode(name.as_bytes()),
                    "value": b64url_encode(value.as_bytes()),
                })
            })
            .collect();

        serde_json::json!({
            "format": self.format,
            "id": self.id,
            "last_tx": self.last_tx,
            "owner": self.owner,
            "tags": tags,
            "target": self.target,
            "quantity": self.quantity,
            "data": data_b64,
            "data_size": self.data_size,
            "data_root": self.data_root,
            "reward": self.reward,
            "signature": self.signature,
        })
    }

    /// Corpo JSON pro `POST /tx` — mesmo formato de `Transaction.toJSON()`
    /// em `arweave-js`: tudo em base64url (inclusive `data` e cada
    /// nome/valor de tag), `tags` como lista de `{name, value}`. Só cobre
    /// conteúdo que caiba em 1 chunk (`data` inline) — pra conteúdo maior,
    /// ver `to_wire_json_no_data`.
    pub(crate) fn to_wire_json(&self) -> serde_json::Value {
        self.to_wire_json_impl(b64url_encode(&self.data))
    }

    /// Mesmo corpo de `to_wire_json`, mas com `data` vazio — usado quando o
    /// conteúdo é publicado via `POST /chunk` em vez de inline (upload em
    /// chunks). `data_size`/`data_root` continuam os valores reais; só o
    /// campo `data` é zerado, espelhando o que `TransactionUploader` faz em
    /// `arweave-js` antes do `POST /tx` de uma tx grande.
    pub(crate) fn to_wire_json_no_data(&self) -> serde_json::Value {
        self.to_wire_json_impl(String::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::arweave::wallet::{jwk_to_private_key, parse_jwk, TEST_WALLET_JWK_JSON};
    use rsa::traits::PublicKeyParts;

    fn test_wallet() -> (crate::arweave::wallet::ArweaveJwk, RsaPrivateKey) {
        let jwk = parse_jwk(TEST_WALLET_JWK_JSON).unwrap();
        let key = jwk_to_private_key(&jwk).unwrap();
        (jwk, key)
    }

    #[test]
    fn lenient_decode_accepts_non_canonical_trailing_bits() {
        // 44 chars, alfabeto base64url válido, mas o último símbolo carrega
        // bits residuais != 0 — mesmo padrão do anchor gerado pelo ArLocal
        // que expôs a necessidade desse decoder (o estrito rejeita).
        let non_canonical = "vq1pzfxj6ba96uc9cyn3qj4hdspa0tlj5s04tfyi1w5";
        assert!(b64url_decode(non_canonical).is_err());
        assert!(b64url_decode_lenient(non_canonical).is_ok());
    }

    #[test]
    fn lenient_decode_matches_strict_decode_for_canonical_input() {
        let canonical = TEST_ANCHOR;
        assert_eq!(
            b64url_decode(canonical).unwrap(),
            b64url_decode_lenient(canonical).unwrap()
        );
    }

    #[test]
    fn build_transaction_fields_are_correct() {
        let data = b"hello vault".to_vec();
        let tx = build_transaction(
            &data,
            &[("Content-Type".to_string(), "application/octet-stream".to_string())],
            "1000",
            "anchor123",
            "owner-n-b64",
        );
        assert_eq!(tx.format, 2);
        assert_eq!(tx.data_size, data.len().to_string());
        assert_eq!(tx.target, "");
        assert_eq!(tx.quantity, "0");
        assert!(!tx.data_root.is_empty());
        assert!(tx.id.is_empty());
        assert!(tx.signature.is_empty());
    }

    #[test]
    fn build_transaction_empty_data_has_empty_data_root() {
        let tx = build_transaction(&[], &[], "1000", "anchor123", "owner-n-b64");
        assert_eq!(tx.data_root, "");
        assert_eq!(tx.data_size, "0");
    }

    #[test]
    fn sign_then_verify_round_trips() {
        let (jwk, key) = test_wallet();
        let mut tx = build_transaction(b"vault blob", &[], "1000", TEST_ANCHOR, &jwk.n);
        sign_transaction(&mut tx, &key).unwrap();
        assert!(!tx.signature.is_empty());
        assert!(!tx.id.is_empty());
        assert!(verify_transaction_signature(&tx, &jwk.e).unwrap());
    }

    #[test]
    fn tampered_data_size_fails_verification() {
        let (jwk, key) = test_wallet();
        let mut tx = build_transaction(b"vault blob", &[], "1000", TEST_ANCHOR, &jwk.n);
        sign_transaction(&mut tx, &key).unwrap();
        tx.data_size = "999999".to_string();
        assert!(!verify_transaction_signature(&tx, &jwk.e).unwrap());
    }

    #[test]
    fn two_signatures_of_same_tx_are_not_identical_bytes() {
        // PSS usa salt aleatório — prova que a assinatura não está usando um
        // salt fixo/zerado por engano (bug histórico comum em wrappers PSS).
        let (jwk, key) = test_wallet();
        let mut tx1 = build_transaction(b"vault blob", &[], "1000", TEST_ANCHOR, &jwk.n);
        let mut tx2 = build_transaction(b"vault blob", &[], "1000", TEST_ANCHOR, &jwk.n);
        sign_transaction(&mut tx1, &key).unwrap();
        sign_transaction(&mut tx2, &key).unwrap();
        assert_ne!(tx1.signature, tx2.signature);
        // mas ambas devem verificar
        assert!(verify_transaction_signature(&tx1, &jwk.e).unwrap());
        assert!(verify_transaction_signature(&tx2, &jwk.e).unwrap());
    }

    // Regressão: `verify_transaction_signature` já assumiu `e = 65537` fixo
    // em vez de ler o expoente real da wallet. A wallet de teste (`test_wallet`)
    // por acaso usa 65537, então os testes acima passam com ou sem o fix —
    // este aqui usa uma chave com expoente não-padrão (17) pra provar que a
    // verificação de fato lê `e` da wallet, não assume um valor fixo.
    #[test]
    fn verify_with_non_standard_public_exponent() {
        let mut rng = rand::thread_rng();
        let exp = BigUint::from(17u32);
        let key = RsaPrivateKey::new_with_exp(&mut rng, 1024, &exp).unwrap();
        let e_b64 = b64url_encode(&key.e().to_bytes_be());
        let n_b64 = b64url_encode(&key.n().to_bytes_be());

        let mut tx = build_transaction(b"vault blob", &[], "1000", TEST_ANCHOR, &n_b64);
        sign_transaction(&mut tx, &key).unwrap();
        assert!(verify_transaction_signature(&tx, &e_b64).unwrap());
    }

    /// Vetor cross-checado contra `arweave-js` (`Transaction.getSignatureData()`
    /// real, com a wallet fixa de teste) — valida a montagem exata dos
    /// campos da tx e a ordem do deep hash, independente da aleatoriedade da
    /// assinatura PSS em si.
    #[test]
    fn cross_checked_signature_data_matches_arweave_js() {
        let (jwk, _key) = test_wallet();
        let data = b"hello arweave vault".to_vec();
        let tx = build_transaction(
            &data,
            &[
                ("Content-Type".to_string(), "application/octet-stream".to_string()),
                ("App-Name".to_string(), "TruthID".to_string()),
            ],
            "1234567",
            TEST_ANCHOR,
            &jwk.n,
        );
        assert_eq!(tx.data_root, "PUnf_1QCJMbVpivlLrf-vD1TBNd1ybPLch49PV0xGSo");
        assert_eq!(tx.data_size, "19");

        let sig_data = signature_data(&tx).unwrap();
        assert_eq!(hex::encode(sig_data), CROSS_CHECKED_SIGDATA_HEX);
    }

    // last_tx/anchor de teste: precisa ser base64url *válido* (canônico) —
    // um placeholder de texto arbitrário como "anchor123" falha ao decodificar
    // (comprimento/bits inválidos) já que `last_tx` é sempre um hash real de
    // 32 bytes na rede de verdade. 32 bytes de 0xAA codificados em base64url.
    const TEST_ANCHOR: &str = "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo";

    const CROSS_CHECKED_SIGDATA_HEX: &str =
        "398db11889bb643a626352169e8f2f777faf98e94351daeaf8a6606135af364df1a936b8e80041b126acb39d67a95b24";
}

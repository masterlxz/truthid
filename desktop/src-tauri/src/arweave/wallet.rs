use rsa::traits::{PrivateKeyParts, PublicKeyParts};
use rsa::{BigUint, RsaPrivateKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Wallet Arweave no formato JWK (RFC 7517), RSA-PSS 4096 bits — mesmo formato
/// usado por `arweave-js`/ArConnect. Todos os campos são base64url sem padding.
#[derive(Serialize, Deserialize, Clone)]
pub(crate) struct ArweaveJwk {
    pub kty: String,
    pub n: String,
    pub e: String,
    pub d: String,
    pub p: String,
    pub q: String,
    pub dp: String,
    pub dq: String,
    pub qi: String,
}

/// `Debug` manual em vez de `derive` — a struct carrega o material privado
/// completo da chave (`d`, `p`, `q`, `dp`, `dq`, `qi`); um `derive(Debug)`
/// vazaria tudo isso pro primeiro `{:?}`/log/painic message que passar por
/// aqui. Só o prefixo do modulus público (`n`) aparece, o suficiente pra
/// identificar a wallet em testes sem arriscar a chave privada.
impl std::fmt::Debug for ArweaveJwk {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ArweaveJwk")
            .field("kty", &self.kty)
            .field("n", &format!("{}...", self.n.get(..12).unwrap_or(&self.n)))
            .field("d", &"[redacted]")
            .field("p", &"[redacted]")
            .field("q", &"[redacted]")
            .finish()
    }
}

fn b64url_encode(bytes: &[u8]) -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    URL_SAFE_NO_PAD.encode(bytes)
}

fn b64url_decode(s: &str) -> Result<Vec<u8>, String> {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    URL_SAFE_NO_PAD.decode(s).map_err(|e| e.to_string())
}

/// Gera uma wallet RSA-4096 nova. Lento (segundos, não-determinístico em
/// tempo — geração de primos é probabilística) — chamar sempre a partir de
/// uma thread bloqueante (`tokio::task::spawn_blocking`), nunca direto na
/// runtime async.
pub(crate) fn generate_jwk() -> Result<ArweaveJwk, String> {
    let mut rng = rand::thread_rng();
    let key = RsaPrivateKey::new(&mut rng, 4096).map_err(|e| e.to_string())?;

    let primes = key.primes();
    if primes.len() != 2 {
        return Err("chave RSA gerada sem exatamente 2 primos".to_string());
    }
    let p = &primes[0];
    let q = &primes[1];
    let dp = key.dp().ok_or("dp ausente após keygen")?;
    let dq = key.dq().ok_or("dq ausente após keygen")?;
    let qi = key.qinv().ok_or("qinv ausente após keygen")?;
    // qinv = q^-1 mod p é sempre positivo por definição matemática;
    // `to_bytes_be()` devolve (Sign, Vec<u8>) só porque o tipo interno é
    // BigInt genérico — descartamos o sinal, os bytes já são a magnitude.
    let (_qi_sign, qi_bytes) = qi.to_bytes_be();

    Ok(ArweaveJwk {
        kty: "RSA".to_string(),
        n: b64url_encode(&key.n().to_bytes_be()),
        e: b64url_encode(&key.e().to_bytes_be()),
        d: b64url_encode(&key.d().to_bytes_be()),
        p: b64url_encode(&p.to_bytes_be()),
        q: b64url_encode(&q.to_bytes_be()),
        dp: b64url_encode(&dp.to_bytes_be()),
        dq: b64url_encode(&dq.to_bytes_be()),
        qi: b64url_encode(&qi_bytes),
    })
}

pub(crate) fn parse_jwk(json: &str) -> Result<ArweaveJwk, String> {
    let jwk: ArweaveJwk =
        serde_json::from_str(json).map_err(|e| format!("JWK inválido: {e}"))?;
    if jwk.kty != "RSA" {
        return Err(format!("kty inesperado (esperado RSA): {}", jwk.kty));
    }
    // Validação de round-trip: reconstrói a chave privada — falha aqui pega
    // JWKs malformados ou com componentes inconsistentes antes de qualquer uso.
    jwk_to_private_key(&jwk)?;
    Ok(jwk)
}

/// Reconstrói a `RsaPrivateKey` a partir dos componentes do JWK. Os campos
/// CRT (`dp`/`dq`/`qi`) não são necessários pra reconstrução — `rsa` os
/// recalcula sozinha a partir de n/e/d/primos — mas são mantidos no JWK por
/// compatibilidade com o formato padrão (RFC 7517 / arweave-js).
pub(crate) fn jwk_to_private_key(jwk: &ArweaveJwk) -> Result<RsaPrivateKey, String> {
    let n = BigUint::from_bytes_be(&b64url_decode(&jwk.n)?);
    let e = BigUint::from_bytes_be(&b64url_decode(&jwk.e)?);
    let d = BigUint::from_bytes_be(&b64url_decode(&jwk.d)?);
    let p = BigUint::from_bytes_be(&b64url_decode(&jwk.p)?);
    let q = BigUint::from_bytes_be(&b64url_decode(&jwk.q)?);

    let key = RsaPrivateKey::from_components(n, e, d, vec![p, q]).map_err(|e| e.to_string())?;
    key.validate().map_err(|e| e.to_string())?;
    Ok(key)
}

/// Endereço da wallet: SHA-256 do modulus `n` (bytes crus, não da string
/// base64url), codificado em base64url sem padding — mesma derivação usada
/// por `arweave-js`.
pub(crate) fn wallet_address(jwk: &ArweaveJwk) -> Result<String, String> {
    let n_bytes = b64url_decode(&jwk.n)?;
    let digest = Sha256::digest(&n_bytes);
    Ok(b64url_encode(&digest))
}

// JWK RSA-4096 real, gerada uma única vez via `generate_jwk()` e versionada
// aqui — evita gerar uma chave 4096 nova a cada `cargo test` (keygen é lento
// e não-determinístico em tempo). Mesmo padrão do vetor ECIES fixo em
// `lib.rs`. Usada também por `transaction.rs` nos próprios testes.
#[cfg(test)]
pub(crate) const TEST_WALLET_JWK_JSON: &str = include_str!("test_fixtures/test_wallet.json");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_fixed_test_wallet() {
        let jwk = parse_jwk(TEST_WALLET_JWK_JSON).expect("fixture deve ser válida");
        assert_eq!(jwk.kty, "RSA");
    }

    #[test]
    fn wallet_address_is_deterministic() {
        let jwk = parse_jwk(TEST_WALLET_JWK_JSON).unwrap();
        let addr1 = wallet_address(&jwk).unwrap();
        let addr2 = wallet_address(&jwk).unwrap();
        assert_eq!(addr1, addr2);
        // endereço Arweave = 32 bytes base64url sem padding = 43 chars
        assert_eq!(addr1.len(), 43);
    }

    #[test]
    fn parse_jwk_rejects_malformed_json() {
        let err = parse_jwk("{not json").unwrap_err();
        assert!(err.contains("JWK inválido"));
    }

    #[test]
    fn parse_jwk_rejects_wrong_kty() {
        let mut jwk: serde_json::Value = serde_json::from_str(TEST_WALLET_JWK_JSON).unwrap();
        jwk["kty"] = serde_json::Value::String("EC".to_string());
        let err = parse_jwk(&jwk.to_string()).unwrap_err();
        assert!(err.contains("kty inesperado"));
    }

    #[test]
    fn round_trip_serialize_parse() {
        let jwk = parse_jwk(TEST_WALLET_JWK_JSON).unwrap();
        let serialized = serde_json::to_string(&jwk).unwrap();
        let reparsed = parse_jwk(&serialized).unwrap();
        assert_eq!(jwk.n, reparsed.n);
        assert_eq!(jwk.d, reparsed.d);
    }

    // Lento (segundos) e com tempo não-determinístico — não roda no
    // `cargo test` do dia a dia, só manualmente / CI dedicado.
    #[test]
    #[ignore]
    fn generate_jwk_produces_valid_wallet() {
        let jwk = generate_jwk().expect("geração deve funcionar");
        let addr = wallet_address(&jwk).expect("endereço deve ser derivável");
        assert_eq!(addr.len(), 43);
        jwk_to_private_key(&jwk).expect("chave deve reconstruir");
    }
}

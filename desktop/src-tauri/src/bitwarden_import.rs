// Import de vault do Bitwarden (Desktop only — extensão não tem autoridade de
// escrita, Mobile normalmente não é onde se gera o export). Duas etapas
// independentes:
//
// 1. `bitwarden_decrypt_export` — só entra em jogo se o arquivo for o export
//    "password protected" do Bitwarden (cifrado com uma senha própria do
//    export, escolhida na hora de exportar — não é a senha mestra da conta).
//    Algoritmo replicado a partir do código-fonte real do próprio Bitwarden
//    (`bitwarden/clients`, `default-key-generation.service.ts`+`enc-string.ts`):
//      a) masterKey = PBKDF2-HMAC-SHA256(password, salt, kdfIterations, 32
//         bytes) — ou Argon2id(password, salt, kdfIterations, kdfMemory MiB,
//         kdfParallelism, 32 bytes) se `kdfType == 1`. `salt` é usado como
//         bytes UTF-8 crus da string do JSON, nunca decodificado de base64
//         antes (mesmo se parecer base64) — confirmado lendo
//         `deriveKeyFromPassword` deles.
//      b) encKey = HKDF-Expand-SHA256(masterKey como PRK, info="enc", 32
//         bytes); macKey = idem com info="mac". Sem etapa de Extract (o
//         masterKey já tem 32 bytes = tamanho de saída do SHA-256, serve
//         direto como PRK) — mesmo "stretchKey" deles.
//      c) Cada `EncString` serializa como "2.<iv_b64>|<data_b64>|<mac_b64>"
//         (tipo 2 = AesCbc256_HmacSha256_B64). Decifra: valida
//         HMAC-SHA256(macKey, iv||data) contra o mac antes de sequer tentar
//         decifrar (comparação em tempo constante via `verify_slice`), depois
//         AES-256-CBC(encKey, iv) com padding PKCS7.
//    `encKeyValidation_DO_NOT_EDIT` é decifrado primeiro só pra confirmar que
//    a senha está certa (mensagem de erro clara em vez de lixo/panic); só
//    depois decifra `data`, que dá o JSON em texto plano no MESMO formato do
//    export sem cifra (mesmo parser do passo 2 reaproveitado).
//
// 2. `bitwarden_parse_export` — mapeia os itens desse JSON (cifrado ou não,
//    não importa) pra `VaultEntry`. Só os tipos `Login` (1) e `Card` (3) têm
//    mapeamento — os demais (SecureNote/Identity/SshKey/...) voltam em
//    `skipped`, reportados na tela, não descartados silenciosamente.

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use cbc::cipher::{BlockDecryptMut, KeyIvInit};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

use crate::vault::{CardNetwork, CreditCardData, EntryType, VaultEntry};

type Aes256CbcDec = cbc::Decryptor<aes::Aes256>;

// ---------------------------------------------------------------------------
// Envelope "password protected" do Bitwarden
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct PasswordProtectedExport {
    encrypted: bool,
    #[serde(rename = "passwordProtected")]
    password_protected: bool,
    salt: String,
    #[serde(rename = "kdfIterations")]
    kdf_iterations: u32,
    #[serde(rename = "kdfMemory")]
    kdf_memory: Option<u32>,
    #[serde(rename = "kdfParallelism")]
    kdf_parallelism: Option<u32>,
    #[serde(rename = "kdfType")]
    kdf_type: u8,
    #[serde(rename = "encKeyValidation_DO_NOT_EDIT")]
    enc_key_validation: String,
    data: String,
}

/// Deriva (encKey, macKey) exatamente como o `stretchKey` do Bitwarden.
fn derive_export_keys(
    password: &str,
    salt: &str,
    kdf_type: u8,
    iterations: u32,
    memory_mib: Option<u32>,
    parallelism: Option<u32>,
) -> Result<([u8; 32], [u8; 32]), String> {
    let mut master_key = [0u8; 32];
    match kdf_type {
        0 => {
            pbkdf2::pbkdf2_hmac::<Sha256>(
                password.as_bytes(),
                salt.as_bytes(),
                iterations,
                &mut master_key,
            );
        }
        1 => {
            let memory_kib = memory_mib.ok_or("Argon2id export sem kdfMemory")? * 1024;
            let parallelism = parallelism.ok_or("Argon2id export sem kdfParallelism")?;
            let params = argon2::Params::new(memory_kib, iterations, parallelism, Some(32))
                .map_err(|e| format!("parâmetros Argon2id inválidos: {e}"))?;
            let argon2 = argon2::Argon2::new(
                argon2::Algorithm::Argon2id,
                argon2::Version::V0x13,
                params,
            );
            argon2
                .hash_password_into(password.as_bytes(), salt.as_bytes(), &mut master_key)
                .map_err(|e| format!("Argon2id falhou: {e}"))?;
        }
        other => return Err(format!("kdfType do Bitwarden não suportado: {other}")),
    }

    let hk = Hkdf::<Sha256>::from_prk(&master_key)
        .map_err(|_| "HKDF from_prk falhou (master key com tamanho errado)".to_string())?;
    let mut enc_key = [0u8; 32];
    let mut mac_key = [0u8; 32];
    hk.expand(b"enc", &mut enc_key)
        .map_err(|_| "HKDF expand (enc) falhou".to_string())?;
    hk.expand(b"mac", &mut mac_key)
        .map_err(|_| "HKDF expand (mac) falhou".to_string())?;
    Ok((enc_key, mac_key))
}

/// Decifra um `EncString` do Bitwarden (`"2.<iv>|<data>|<mac>"`, base64 em
/// cada parte). Só o tipo 2 (AesCbc256_HmacSha256_B64) é suportado — é o
/// único tipo usado pelo formato de export "password protected".
fn decrypt_enc_string(enc_string: &str, enc_key: &[u8; 32], mac_key: &[u8; 32]) -> Result<Vec<u8>, String> {
    let rest = enc_string
        .strip_prefix("2.")
        .ok_or("EncString não é do tipo 2 (AesCbc256_HmacSha256_B64)".to_string())?;
    let parts: Vec<&str> = rest.split('|').collect();
    if parts.len() != 3 {
        return Err("EncString malformado (esperado iv|data|mac)".to_string());
    }
    let iv = B64.decode(parts[0]).map_err(|e| e.to_string())?;
    let data = B64.decode(parts[1]).map_err(|e| e.to_string())?;
    let mac = B64.decode(parts[2]).map_err(|e| e.to_string())?;

    let mut mac_verifier =
        Hmac::<Sha256>::new_from_slice(mac_key).map_err(|e| e.to_string())?;
    mac_verifier.update(&iv);
    mac_verifier.update(&data);
    mac_verifier
        .verify_slice(&mac)
        .map_err(|_| "senha errada ou arquivo corrompido (MAC não confere)".to_string())?;

    let iv: [u8; 16] = iv
        .try_into()
        .map_err(|_| "IV do EncString não tem 16 bytes".to_string())?;
    Aes256CbcDec::new(enc_key.into(), &iv.into())
        .decrypt_padded_vec_mut::<cbc::cipher::block_padding::Pkcs7>(&data)
        .map_err(|_| "decifra AES-CBC falhou (senha errada ou dado corrompido)".to_string())
}

/// Recebe o conteúdo bruto do arquivo `.json` do export "password
/// protected" do Bitwarden + a senha do export (não é a senha mestra da
/// conta) e devolve o JSON em texto plano (formato sem cifra), pronto pra
/// `bitwarden_parse_export`.
#[tauri::command]
pub(crate) fn bitwarden_decrypt_export(data: String, password: String) -> Result<String, String> {
    let envelope: PasswordProtectedExport =
        serde_json::from_str(&data).map_err(|e| format!("JSON inválido: {e}"))?;
    if !envelope.encrypted || !envelope.password_protected {
        return Err("arquivo não é um export cifrado do Bitwarden".to_string());
    }

    let (enc_key, mac_key) = derive_export_keys(
        &password,
        &envelope.salt,
        envelope.kdf_type,
        envelope.kdf_iterations,
        envelope.kdf_memory,
        envelope.kdf_parallelism,
    )?;

    // Valida a senha primeiro — mensagem de erro clara em vez de um erro
    // genérico de parse na hora de decifrar `data`.
    decrypt_enc_string(&envelope.enc_key_validation, &enc_key, &mac_key)
        .map_err(|_| "senha do export incorreta".to_string())?;

    let plaintext = decrypt_enc_string(&envelope.data, &enc_key, &mac_key)?;
    String::from_utf8(plaintext).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Parse do JSON (sem cifra, ou já decifrado pelo passo acima) -> VaultEntry
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct BitwardenExport {
    #[serde(default)]
    folders: Vec<BitwardenFolder>,
    items: Vec<BitwardenItem>,
}

#[derive(Deserialize)]
struct BitwardenFolder {
    id: String,
    name: String,
}

#[derive(Deserialize)]
struct BitwardenItem {
    #[serde(rename = "folderId")]
    folder_id: Option<String>,
    r#type: u8,
    name: String,
    #[serde(default)]
    notes: Option<String>,
    #[serde(default)]
    fields: Vec<BitwardenField>,
    login: Option<BitwardenLogin>,
    card: Option<BitwardenCard>,
}

#[derive(Deserialize)]
struct BitwardenField {
    name: Option<String>,
    value: Option<String>,
}

#[derive(Deserialize)]
struct BitwardenLogin {
    #[serde(default)]
    uris: Vec<BitwardenUri>,
    username: Option<String>,
    password: Option<String>,
    totp: Option<String>,
}

#[derive(Deserialize)]
struct BitwardenUri {
    uri: Option<String>,
}

#[derive(Deserialize)]
struct BitwardenCard {
    #[serde(rename = "cardholderName")]
    cardholder_name: Option<String>,
    brand: Option<String>,
    number: Option<String>,
    #[serde(rename = "expMonth")]
    exp_month: Option<String>,
    #[serde(rename = "expYear")]
    exp_year: Option<String>,
    code: Option<String>,
}

const CIPHER_TYPE_LOGIN: u8 = 1;
const CIPHER_TYPE_CARD: u8 = 3;

#[derive(Serialize)]
pub(crate) struct SkippedItem {
    name: String,
    reason: String,
}

#[derive(Serialize)]
pub(crate) struct ImportCandidate {
    #[serde(flatten)]
    entry: VaultEntry,
    /// Id da entrada existente que parece ser a mesma (mesmo site/url +
    /// username) — `None` se não achou nenhuma parecida. Decisão do que
    /// fazer (pular/sobrescrever/importar como nova) fica pra tela.
    possible_duplicate_id: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct BitwardenImportPreview {
    candidates: Vec<ImportCandidate>,
    skipped: Vec<SkippedItem>,
}

/// Se `totp` vier como uma URI `otpauth://...`, extrai só o parâmetro
/// `secret`. Senão assume que já é o segredo base32 cru (caso comum de um
/// export direto do Bitwarden).
fn normalize_totp(totp: &str) -> String {
    if let Some(query_start) = totp.find('?') {
        for pair in totp[query_start + 1..].split('&') {
            if let Some(value) = pair.strip_prefix("secret=") {
                return value.to_string();
            }
        }
    }
    totp.to_string()
}

fn map_card_brand(brand: &str) -> CardNetwork {
    match brand.to_ascii_lowercase().as_str() {
        "visa" => CardNetwork::Visa,
        "mastercard" => CardNetwork::Mastercard,
        "amex" => CardNetwork::Amex,
        "elo" => CardNetwork::Elo,
        "hipercard" => CardNetwork::Hipercard,
        _ => CardNetwork::Other,
    }
}

fn normalize_for_match(s: &str) -> String {
    s.trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_end_matches('/')
        .to_ascii_lowercase()
}

fn find_duplicate(candidate: &VaultEntry, existing: &[VaultEntry]) -> Option<String> {
    if candidate.r#type != EntryType::Credential || candidate.username.is_empty() {
        return None;
    }
    let candidate_key = (
        normalize_for_match(&candidate.url),
        candidate.username.to_ascii_lowercase(),
    );
    existing
        .iter()
        .find(|e| {
            e.r#type == EntryType::Credential
                && (normalize_for_match(&e.url), e.username.to_ascii_lowercase()) == candidate_key
        })
        .map(|e| e.id.clone())
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn build_notes(item_notes: &Option<String>, fields: &[BitwardenField]) -> String {
    let mut notes = item_notes.clone().unwrap_or_default();
    for field in fields {
        let (Some(name), Some(value)) = (&field.name, &field.value) else {
            continue;
        };
        if value.is_empty() {
            continue;
        }
        if !notes.is_empty() {
            notes.push('\n');
        }
        notes.push_str(&format!("{name}: {value}"));
    }
    notes
}

/// Mapeia o JSON do export do Bitwarden (já em texto plano, cifrado ou não
/// antes) pros candidatos de `VaultEntry`. Só os tipos `Login`/`Card` viram
/// entrada de verdade — o resto entra em `skipped`, reportado explicitamente
/// na tela em vez de descartado sem aviso.
#[tauri::command]
pub(crate) fn bitwarden_parse_export(json: String) -> Result<BitwardenImportPreview, String> {
    let export: BitwardenExport =
        serde_json::from_str(&json).map_err(|e| format!("JSON do Bitwarden inválido: {e}"))?;
    let existing = crate::vault::load()?.entries;

    let mut candidates = Vec::new();
    let mut skipped = Vec::new();
    let now = now_secs();

    for item in export.items {
        let profile = item
            .folder_id
            .as_deref()
            .and_then(|fid| export.folders.iter().find(|f| f.id == fid))
            .map(|f| f.name.clone());
        let profiles = profile.map(|p| vec![p]).unwrap_or_default();

        let entry = match item.r#type {
            CIPHER_TYPE_LOGIN => {
                let login = item.login.unwrap_or(BitwardenLogin {
                    uris: vec![],
                    username: None,
                    password: None,
                    totp: None,
                });
                VaultEntry {
                    id: String::new(),
                    site: item.name,
                    url: login.uris.first().and_then(|u| u.uri.clone()).unwrap_or_default(),
                    username: login.username.unwrap_or_default(),
                    password: login.password.unwrap_or_default(),
                    notes: build_notes(&item.notes, &item.fields),
                    profiles,
                    profile: String::new(),
                    totp_secret: login.totp.as_deref().map(normalize_totp),
                    passkey: None,
                    favorite: false,
                    r#type: EntryType::Credential,
                    document: None,
                    address: None,
                    credit_card: None,
                    created_at: now,
                    updated_at: now,
                }
            }
            CIPHER_TYPE_CARD => {
                let card = item.card.unwrap_or(BitwardenCard {
                    cardholder_name: None,
                    brand: None,
                    number: None,
                    exp_month: None,
                    exp_year: None,
                    code: None,
                });
                VaultEntry {
                    id: String::new(),
                    site: String::new(),
                    url: String::new(),
                    username: String::new(),
                    password: String::new(),
                    notes: build_notes(&item.notes, &item.fields),
                    profiles,
                    profile: String::new(),
                    totp_secret: None,
                    passkey: None,
                    favorite: false,
                    r#type: EntryType::CreditCard,
                    document: None,
                    address: None,
                    credit_card: Some(CreditCardData {
                        label: item.name,
                        card_holder_name: card.cardholder_name.unwrap_or_default(),
                        card_number: card.number.unwrap_or_default(),
                        expiry_month: card.exp_month.unwrap_or_default(),
                        expiry_year: card.exp_year.unwrap_or_default(),
                        cvv: card.code.unwrap_or_default(),
                        bank: None,
                        card_network: card.brand.as_deref().map(map_card_brand).unwrap_or(CardNetwork::Other),
                    }),
                    created_at: now,
                    updated_at: now,
                }
            }
            other => {
                skipped.push(SkippedItem {
                    name: item.name,
                    reason: format!("tipo de item não suportado (código {other})"),
                });
                continue;
            }
        };

        let possible_duplicate_id = find_duplicate(&entry, &existing);
        candidates.push(ImportCandidate {
            entry,
            possible_duplicate_id,
        });
    }

    Ok(BitwardenImportPreview { candidates, skipped })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_totp_extracts_secret_from_otpauth_uri() {
        assert_eq!(
            normalize_totp("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"),
            "JBSWY3DPEHPK3PXP"
        );
    }

    #[test]
    fn normalize_totp_passes_through_raw_base32() {
        assert_eq!(normalize_totp("JBSWY3DPEHPK3PXP"), "JBSWY3DPEHPK3PXP");
    }

    #[test]
    fn map_card_brand_matches_known_networks_case_insensitively() {
        assert_eq!(map_card_brand("Visa"), CardNetwork::Visa);
        assert_eq!(map_card_brand("MASTERCARD"), CardNetwork::Mastercard);
        assert_eq!(map_card_brand("discover"), CardNetwork::Other);
    }

    #[test]
    fn parse_export_maps_login_and_card_and_skips_unsupported() {
        let json = serde_json::json!({
            "encrypted": false,
            "folders": [{"id": "f1", "name": "Trabalho"}],
            "items": [
                {
                    "id": "1", "folderId": "f1", "type": 1, "name": "GitHub", "notes": "conta pessoal",
                    "fields": [{"name": "recovery", "value": "codes-here", "type": 0}],
                    "login": {
                        "uris": [{"uri": "https://github.com"}],
                        "username": "alice", "password": "hunter2",
                        "totp": "otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP"
                    }
                },
                {
                    "id": "2", "type": 3, "name": "Nubank",
                    "card": {"cardholderName": "Alice", "brand": "visa", "number": "4242424242424242", "expMonth": "04", "expYear": "2030", "code": "123"}
                },
                {"id": "3", "type": 4, "name": "Minha identidade"}
            ]
        })
        .to_string();

        let preview = bitwarden_parse_export(json).unwrap();
        assert_eq!(preview.candidates.len(), 2);
        assert_eq!(preview.skipped.len(), 1);
        assert_eq!(preview.skipped[0].name, "Minha identidade");

        let login = &preview.candidates[0].entry;
        assert_eq!(login.site, "GitHub");
        assert_eq!(login.url, "https://github.com");
        assert_eq!(login.username, "alice");
        assert_eq!(login.password, "hunter2");
        assert_eq!(login.profiles, vec!["Trabalho".to_string()]);
        assert_eq!(login.totp_secret.as_deref(), Some("JBSWY3DPEHPK3PXP"));
        assert!(login.notes.contains("conta pessoal"));
        assert!(login.notes.contains("recovery: codes-here"));

        let card = &preview.candidates[1].entry;
        assert_eq!(card.r#type, EntryType::CreditCard);
        let cc = card.credit_card.as_ref().unwrap();
        assert_eq!(cc.card_number, "4242424242424242");
        assert_eq!(cc.card_network, CardNetwork::Visa);
    }

    #[test]
    fn parse_export_marks_possible_duplicate_by_url_and_username() {
        // `find_duplicate` só compara contra o que já existe no vault local
        // (`vault::load()`) — este teste roda num ambiente sem vault (novo),
        // então só confirma que 0 duplicatas são achadas quando não há nada
        // pra bater (regressão: não deveria dar falso-positivo).
        let json = serde_json::json!({
            "encrypted": false,
            "items": [{
                "id": "1", "type": 1, "name": "GitHub",
                "login": {"uris": [{"uri": "https://github.com"}], "username": "alice", "password": "x"}
            }]
        })
        .to_string();
        let preview = bitwarden_parse_export(json).unwrap();
        assert_eq!(preview.candidates[0].possible_duplicate_id, None);
    }

    /// Fixture construída à mão (não é o fixture real do Bitwarden — o deles
    /// não expõe a senha usada pra criá-lo, só os bytes cifrados) — cifra um
    /// payload conhecido com os mesmos primitivos (PBKDF2+HKDF+AES-CBC+HMAC)
    /// e confirma que a decifra reverte certo. Valida a mecânica, não
    /// interop byte-a-byte contra um export real do Bitwarden.
    #[test]
    fn decrypt_export_round_trips_with_hand_built_fixture() {
        use cbc::cipher::BlockEncryptMut;

        let password = "correct horse battery staple";
        let salt = "Oy0xcgVRzxQ+9NpB5GLehw==";
        let iterations = 100_000u32;
        let (enc_key, mac_key) =
            derive_export_keys(password, salt, 0, iterations, None, None).unwrap();

        let plaintext = br#"{"encrypted":false,"items":[]}"#;
        let iv = [7u8; 16];
        let mut buf = plaintext.to_vec();
        buf.resize(plaintext.len() + 16 - (plaintext.len() % 16), 0);
        let ct_len = cbc::Encryptor::<aes::Aes256>::new(&enc_key.into(), &iv.into())
            .encrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buf, plaintext.len())
            .unwrap()
            .len();
        buf.truncate(ct_len);

        let mut mac = Hmac::<Sha256>::new_from_slice(&mac_key).unwrap();
        mac.update(&iv);
        mac.update(&buf);
        let mac_bytes = mac.finalize().into_bytes();

        let enc_string = format!(
            "2.{}|{}|{}",
            B64.encode(iv),
            B64.encode(&buf),
            B64.encode(mac_bytes)
        );

        let decrypted = decrypt_enc_string(&enc_string, &enc_key, &mac_key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn decrypt_export_rejects_wrong_password() {
        use cbc::cipher::BlockEncryptMut;

        let salt = "Oy0xcgVRzxQ+9NpB5GLehw==";
        let (enc_key, mac_key) =
            derive_export_keys("right-password", salt, 0, 100_000, None, None).unwrap();

        let plaintext = b"secret";
        let iv = [1u8; 16];
        let mut buf = plaintext.to_vec();
        buf.resize(32, 0);
        let ct_len = cbc::Encryptor::<aes::Aes256>::new(&enc_key.into(), &iv.into())
            .encrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buf, plaintext.len())
            .unwrap()
            .len();
        buf.truncate(ct_len);
        let mut mac = Hmac::<Sha256>::new_from_slice(&mac_key).unwrap();
        mac.update(&iv);
        mac.update(&buf);
        let enc_string = format!(
            "2.{}|{}|{}",
            B64.encode(iv),
            B64.encode(&buf),
            B64.encode(mac.finalize().into_bytes())
        );

        let (wrong_enc_key, wrong_mac_key) =
            derive_export_keys("wrong-password", salt, 0, 100_000, None, None).unwrap();
        assert!(decrypt_enc_string(&enc_string, &wrong_enc_key, &wrong_mac_key).is_err());
    }
}

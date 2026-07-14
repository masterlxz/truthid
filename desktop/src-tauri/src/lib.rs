use hkdf::Hkdf;
use k256::ecdsa::SigningKey;
use k256::PublicKey;
use keyring::Entry;
use rand::rngs::OsRng;
use sha2::Sha256;
use sha3::{Digest, Keccak256};
use aes_gcm::{Aes256Gcm, Key};
use aes_gcm::aead::{Aead, AeadCore, KeyInit};
use k256::elliptic_curve::ecdh::diffie_hellman;

mod ipfs;
mod ledger;
mod vault;

const SERVICE: &str = "truthid";
const ACCOUNT: &str = "device-private-key";
const VAULT_KEY_ACCOUNT: &str = "vault-key";

/// Caminho de fallback quando o keyring do SO não está disponível (ex: Docker).
/// Usa $HOME/.truthid/device.key — montado como volume no compose para persistir.
fn fallback_key_path() -> Result<std::path::PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("device.key"))
}

/// Lê a chave privada do keyring ou do arquivo de fallback.
/// Gera e salva uma nova chave se nenhuma existir.
fn get_device_key_hex() -> Result<String, String> {
    // 1. Tenta keyring do SO
    if let Ok(entry) = Entry::new(SERVICE, ACCOUNT) {
        if let Ok(hex) = entry.get_password() {
            return Ok(hex);
        }
    }

    // 2. Fallback: arquivo ($HOME/.truthid/device.key)
    let path = fallback_key_path()?;
    if path.exists() {
        return std::fs::read_to_string(&path)
            .map(|s| s.trim().to_string())
            .map_err(|e| e.to_string());
    }

    // 3. Gera nova chave secp256k1
    let signing_key = SigningKey::random(&mut OsRng);
    let hex = hex::encode(signing_key.to_bytes());

    // Salva no keyring; se falhar, salva no arquivo
    let saved = Entry::new(SERVICE, ACCOUNT)
        .and_then(|e| e.set_password(&hex))
        .is_ok();

    if !saved {
        std::fs::write(&path, &hex).map_err(|e| e.to_string())?;
    }

    Ok(hex)
}

/// Deriva a chave de criptografia do vault a partir da chave privada do device
/// (esquema antigo, pré-Fase 13.8). Mantida apenas para migração de vaults
/// existentes — novos vaults usam `derive_vault_key_from_wallet`.
///
/// Usa HKDF-SHA256 (RFC 5869). A chave privada do device é o IKM; o resultado
/// é uma chave AES-256 de 32 bytes usada apenas para cifrar o vault — nunca
/// para assinar nada. Isolamento por propósito: mudar `info` geraria uma chave
/// completamente diferente, mesmo com o mesmo device.
pub(crate) fn derive_vault_key_legacy() -> Result<[u8; 32], String> {
    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;

    let hk = Hkdf::<Sha256>::new(Some(b"TruthID"), &priv_bytes);
    let mut okm = [0u8; 32];
    hk.expand(b"vault-key-v1", &mut okm)
        .map_err(|_| "HKDF expand failed".to_string())?;
    Ok(okm)
}

/// Lê a chave do vault do keyring do SO.
/// Se nenhuma chave foi derivada da wallet ainda, usa a chave legada
/// (device-key) como fallback temporário — a migração acontece no próximo
/// `load()` quando a wallet assinar.
pub(crate) fn get_vault_key() -> Result<[u8; 32], String> {
    // 1. Tenta keyring do SO (chave nova, wallet-derived)
    if let Ok(entry) = Entry::new(SERVICE, VAULT_KEY_ACCOUNT) {
        if let Ok(hex) = entry.get_password() {
            let bytes = hex::decode(&hex).map_err(|e| e.to_string())?;
            if bytes.len() == 32 {
                let mut key = [0u8; 32];
                key.copy_from_slice(&bytes);
                return Ok(key);
            }
        }
    }

    // 2. Fallback: arquivo ($HOME/.truthid/vault.key)
    let path = vault_key_path()?;
    if path.exists() {
        let hex = std::fs::read_to_string(&path)
            .map_err(|e| e.to_string())?;
        let bytes = hex::decode(hex.trim()).map_err(|e| e.to_string())?;
        if bytes.len() == 32 {
            let mut key = [0u8; 32];
            key.copy_from_slice(&bytes);
            return Ok(key);
        }
    }

    // 3. Fallback legacy: chave derivada do device (pré-migração)
    //    Mantém compatibilidade com vaults existentes e testes unitários
    //    que não passaram pelo fluxo de assinatura da wallet.
    derive_vault_key_legacy()
}

fn vault_key_path() -> Result<std::path::PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("vault.key"))
}

fn set_vault_key(key: &[u8; 32]) -> Result<(), String> {
    let hex_key = hex::encode(key);

    // Salva no keyring do SO
    let saved = Entry::new(SERVICE, VAULT_KEY_ACCOUNT)
        .and_then(|e| e.set_password(&hex_key))
        .is_ok();

    // Fallback: arquivo
    if !saved {
        let path = vault_key_path()?;
        std::fs::write(&path, &hex_key).map_err(|e| e.to_string())?;
    }

    Ok(())
}

/// Verifica se a chave do vault já foi derivada (existe no keyring).
#[tauri::command]
fn vault_key_exists() -> Result<bool, String> {
    if let Ok(entry) = Entry::new(SERVICE, VAULT_KEY_ACCOUNT) {
        if entry.get_password().is_ok() {
            return Ok(true);
        }
    }
    let path = vault_key_path()?;
    Ok(path.exists())
}

/// Deriva a chave AES-256 do vault a partir de uma assinatura ECDSA da wallet.
///
/// A wallet (Ledger, MetaMask, etc.) assina a mensagem fixa
/// `"TruthID Vault Key v1"` via `personal_sign`. Como carteiras modernas usam
/// RFC 6979 (k determinístico), a mesma wallet + mesma mensagem produz sempre
/// a mesma assinatura — permitindo re-derivar a chave do vault em qualquer
/// dispositivo, sem armazenar nada.
///
/// Parâmetros:
/// - `r`, `s`: componentes da assinatura (hex, com prefixo 0x)
/// - `v`: recovery id (0 ou 1, convertido pelo frontend a partir do v do eip-191)
///
/// A chave resultante é armazenada no keyring do SO para uso futuro
/// (não é necessário re-conectar a wallet no dia a dia).
#[tauri::command]
fn derive_vault_key_from_wallet(r: String, s: String, v: u8) -> Result<(), String> {
    let r_bytes = hex::decode(r.trim_start_matches("0x")).map_err(|e| e.to_string())?;
    let s_bytes = hex::decode(s.trim_start_matches("0x")).map_err(|e| e.to_string())?;

    if r_bytes.len() != 32 || s_bytes.len() != 32 {
        return Err("r and s must each be 32 bytes".to_string());
    }

    // Concatena r || s || v como IKM para o HKDF
    let mut ikm = Vec::with_capacity(65);
    ikm.extend_from_slice(&r_bytes);
    ikm.extend_from_slice(&s_bytes);
    ikm.push(v);

    // Deriva chave AES-256 via HKDF-SHA256
    // info="vault-key-v2" é diferente de "vault-key-v1" (legacy, device-key-based)
    // para garantir isolamento criptográfico entre os dois esquemas.
    let hk = Hkdf::<Sha256>::new(Some(b"TruthID"), &ikm);
    let mut okm = [0u8; 32];
    hk.expand(b"vault-key-v2", &mut okm)
        .map_err(|_| "HKDF expand failed".to_string())?;

    set_vault_key(&okm)
}

/// Retorna o endereço Ethereum da chave pública deste desktop.
/// Gera e persiste a chave se ainda não existir.
#[tauri::command]
fn get_or_create_device_key() -> Result<String, String> {
    let priv_hex = get_device_key_hex()?;

    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let signing_key = SigningKey::from_bytes(priv_bytes.as_slice().into())
        .map_err(|e| e.to_string())?;

    // Chave pública não-comprimida: 0x04 + X (32 bytes) + Y (32 bytes) = 65 bytes
    let pub_point = signing_key.verifying_key().to_encoded_point(false);
    let pub_bytes = pub_point.as_bytes();

    // Endereço Ethereum = últimos 20 bytes do keccak256(pubkey sem o prefixo 0x04)
    let hash = Keccak256::digest(&pub_bytes[1..]);
    let address = format!("0x{}", hex::encode(&hash[12..]));

    Ok(address)
}

/// Signs a 32-byte session hash for on-chain createSession.
/// The contract verifies: ecrecover(keccak256("\x19Ethereum Signed Message:\n32" + hash), v, r, s) == devicePubKey
/// Returns (r, s, v) as separate values so the caller can pass them as distinct ABI arguments.
#[tauri::command]
fn sign_session_hash(hash: String) -> Result<(String, String, u8), String> {
    let hash_bytes = hex::decode(hash.trim_start_matches("0x"))
        .map_err(|e| format!("invalid hash hex: {e}"))?;
    if hash_bytes.len() != 32 {
        return Err(format!("hash must be 32 bytes, got {}", hash_bytes.len()));
    }

    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let signing_key = SigningKey::from_bytes(priv_bytes.as_slice().into())
        .map_err(|e| e.to_string())?;

    // Ethereum personal_sign of 32 raw bytes — same prefix the contract uses:
    // keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash))
    let prefix = b"\x19Ethereum Signed Message:\n32";
    let mut msg = Vec::with_capacity(prefix.len() + 32);
    msg.extend_from_slice(prefix);
    msg.extend_from_slice(&hash_bytes);
    let digest = Keccak256::digest(&msg);

    let (signature, recovery_id) = signing_key
        .sign_prehash_recoverable(&digest)
        .map_err(|e| e.to_string())?;

    let sig_bytes = signature.to_bytes();
    let r = format!("0x{}", hex::encode(&sig_bytes[..32]));
    let s = format!("0x{}", hex::encode(&sig_bytes[32..]));
    let v = recovery_id.to_byte() + 27u8;

    Ok((r, s, v))
}

/// Lista todas as entradas do vault local (decifrado em memória).
#[tauri::command]
fn vault_list_entries() -> Result<Vec<vault::VaultEntry>, String> {
    Ok(vault::load()?.entries)
}

/// Cria ou atualiza uma entrada do vault.
/// Se `entry.id` estiver vazio, gera um novo id. Persiste em disco.
#[tauri::command]
fn vault_upsert_entry(entry: vault::VaultEntry) -> Result<vault::VaultEntry, String> {
    let mut v = vault::load()?;
    let saved = v.upsert(entry);
    vault::save(&v)?;
    Ok(saved)
}

/// Remove uma entrada do vault pelo id. Persiste em disco.
#[tauri::command]
fn vault_delete_entry(id: String) -> Result<(), String> {
    let mut v = vault::load()?;
    v.delete(&id);
    vault::save(&v)
}

/// Lista os nomes de perfis criados pelo usuário.
#[tauri::command]
fn vault_list_profiles() -> Result<Vec<String>, String> {
    Ok(vault::load()?.profile_names)
}

/// Cria um novo perfil (nome livre). Persiste em disco.
#[tauri::command]
fn vault_add_profile(name: String) -> Result<(), String> {
    let mut v = vault::load()?;
    v.add_profile(&name);
    vault::save(&v)
}

/// Renomeia um perfil e atualiza em cascata as entradas que o usam. Persiste em disco.
#[tauri::command]
fn vault_rename_profile(old_name: String, new_name: String) -> Result<(), String> {
    let mut v = vault::load()?;
    v.rename_profile(&old_name, &new_name);
    vault::save(&v)
}

/// Remove um perfil e limpa a tag das entradas que o usam. Persiste em disco.
#[tauri::command]
fn vault_delete_profile(name: String) -> Result<(), String> {
    let mut v = vault::load()?;
    v.delete_profile(&name);
    vault::save(&v)
}

/// Cifra a chave do vault com a chave pública de um device (ECIES secp256k1)
/// para compartilhamento durante o pareamento.
///
/// Recebe a chave pública não-comprimida do device (hex, 130 chars = 65 bytes)
/// e retorna o blob cifrado em Base64:
///   ephemeral_pubkey(33 bytes comprimida) || nonce(12) || ciphertext+tag
///
/// O device destino usa sua chave privada para fazer ECDH com a ephemeral_pubkey,
/// derivar a mesma chave AES e decifrar a vault_key.
#[tauri::command]
fn encrypt_vault_key_for_device(device_pubkey_hex: String) -> Result<String, String> {
    let vault_key = get_vault_key()?;
    encrypt_bytes_for_device(&vault_key, &device_pubkey_hex)
}

// Lógica pura (sem keyring/filesystem) extraída de encrypt_vault_key_for_device
// pra poder testar o round-trip ECIES sem precisar mockar get_vault_key().
fn encrypt_bytes_for_device(vault_key: &[u8], device_pubkey_hex: &str) -> Result<String, String> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    use k256::elliptic_curve::sec1::FromEncodedPoint;

    let pubkey_hex = device_pubkey_hex.trim_start_matches("0x");
    let pubkey_bytes = hex::decode(pubkey_hex).map_err(|e| e.to_string())?;

    if pubkey_bytes.len() != 33 && pubkey_bytes.len() != 65 {
        return Err("device_pubkey must be 33-byte (compressed) or 65-byte (uncompressed) secp256k1 key".to_string());
    }

    // Converte os bytes para uma chave pública k256
    let point = k256::EncodedPoint::from_bytes(&pubkey_bytes)
        .map_err(|e| e.to_string())?;
    let device_pub = PublicKey::from_encoded_point(&point)
        .into_option()
        .ok_or_else(|| "invalid public key".to_string())?;

    // Gera par efêmero
    let ephemeral_priv = SigningKey::random(&mut OsRng);
    let ephemeral_pub = ephemeral_priv.verifying_key();

    // ECDH: shared_secret = ephemeral_priv * device_pub
    let shared = diffie_hellman(
        ephemeral_priv.as_nonzero_scalar(),
        device_pub.as_affine(),
    );
    let shared_bytes = shared.raw_secret_bytes();

    // Deriva chave AES do shared secret via SHA-256 — sem isso, a chave AES
    // era o segredo ECDH cru (32 bytes), diferente da chave que o mobile
    // deriva (que sempre fez o hash corretamente em decryptVaultKeyFromPairing).
    // Bug presente desde a Sessão 76: toda vault key entregue via pareamento
    // falhava na decifra no mobile com erro de MAC, mesmo com o blob correto
    // on-chain — só descoberto agora testando de ponta a ponta com dados reais.
    let aes_key_bytes = Sha256::digest(shared_bytes);
    let aes_key = Key::<Aes256Gcm>::from_slice(&aes_key_bytes);

    // Cifra a vault_key com AES-256-GCM
    let cipher = Aes256Gcm::new(aes_key);
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(&nonce, vault_key)
        .map_err(|_| "ECIES encrypt failed".to_string())?;

    // Formato do blob: ephemeral_pubkey(33 comprimida) || nonce(12) || ciphertext+tag
    let ephemeral_bytes = ephemeral_pub.to_encoded_point(true); // comprimida
    let mut blob = Vec::with_capacity(33 + 12 + ciphertext.len());
    blob.extend_from_slice(ephemeral_bytes.as_bytes());
    blob.extend_from_slice(&nonce);
    blob.extend_from_slice(&ciphertext);

    Ok(STANDARD.encode(blob))
}
/// Cifra dados com AES-256-GCM usando a chave do vault.
/// Entrada: plaintext em Base64. Saída: blob cifrado em Base64 (nonce+cipher+tag).
#[tauri::command]
fn vault_encrypt(plaintext_b64: String) -> Result<String, String> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let plaintext = STANDARD.decode(&plaintext_b64).map_err(|e| e.to_string())?;
    let blob = vault::encrypt(&plaintext)?;
    Ok(STANDARD.encode(blob))
}

/// Publica o vault local no IPFS (upload multi-pin) e retorna o CID e o
/// content hash (keccak256) para o frontend registrar no VaultRegistry.
/// Requer ao menos um provider `kind = "kubo"` configurado.
#[tauri::command]
async fn vault_publish() -> Result<ipfs::PinResult, String> {
    let path = vault::vault_path()?;
    if !path.exists() {
        return Err("vault ainda não existe — adicione ao menos uma entrada antes de publicar".to_string());
    }
    let encrypted_blob = std::fs::read(&path).map_err(|e| e.to_string())?;
    let providers = ipfs::load_providers();
    if providers.is_empty() {
        return Err("nenhum provider de pinning configurado — use vault_set_providers primeiro".to_string());
    }
    let result = ipfs::pin_vault(&encrypted_blob, &providers).await?;
    // Registra a versão atual como publicada
    let v = vault::load()?;
    vault::mark_published(v.version)?;
    Ok(result)
}

/// Quantas edições locais ainda não foram publicadas no IPFS.
/// 0 = vault está em sync com o último "Enviar".
#[tauri::command]
fn vault_pending_changes() -> Result<u64, String> {
    vault::pending_changes()
}

/// Retorna a lista de providers de pinning configurados.
#[tauri::command]
fn vault_get_providers() -> Result<Vec<ipfs::PinningProvider>, String> {
    Ok(ipfs::load_providers())
}

/// Salva a lista de providers de pinning.
#[tauri::command]
fn vault_set_providers(providers: Vec<ipfs::PinningProvider>) -> Result<(), String> {
    ipfs::save_providers(&providers)
}

/// Retorna a permissão canWriteVault de cada device — mora dentro do próprio
/// vault desde a Sessão 97 (antes era um arquivo local separado), pra viajar
/// no blob sincronizado e o Mobile conseguir ler a própria permissão.
#[tauri::command]
fn vault_get_device_permissions() -> Result<Vec<vault::DeviceVaultPermission>, String> {
    Ok(vault::load()?.device_permissions)
}

/// Define ou atualiza a permissão canWriteVault de um device (por pubKey).
/// Persiste em disco.
#[tauri::command]
fn vault_set_device_permission(pub_key: String, can_write: bool) -> Result<(), String> {
    let mut v = vault::load()?;
    v.set_device_permission(&pub_key, can_write);
    vault::save(&v)
}

/// Decifra um blob gerado por vault_encrypt.
/// Entrada: blob em Base64. Saída: plaintext em Base64.
#[tauri::command]
fn vault_decrypt(blob_b64: String) -> Result<String, String> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let blob = STANDARD.decode(&blob_b64).map_err(|e| e.to_string())?;
    let plaintext = vault::decrypt(&blob)?;
    Ok(STANDARD.encode(plaintext))
}

/// Signs a challenge with this desktop's private key.
/// Returns the signature in Ethereum format: 0x + r (32 bytes) + s (32 bytes) + v (1 byte).
#[tauri::command]
fn sign_challenge(challenge: String) -> Result<String, String> {
    let priv_hex = get_device_key_hex()?;

    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let signing_key = SigningKey::from_bytes(priv_bytes.as_slice().into())
        .map_err(|e| e.to_string())?;

    // Ethereum personal_sign format: keccak256("\x19Ethereum Signed Message:\n{len}{message}")
    // Matches what viem's recoverMessageAddress() expects on the server side.
    let msg_bytes = challenge.as_bytes();
    let prefix = format!("\x19Ethereum Signed Message:\n{}", msg_bytes.len());
    let mut prefixed = Vec::with_capacity(prefix.len() + msg_bytes.len());
    prefixed.extend_from_slice(prefix.as_bytes());
    prefixed.extend_from_slice(msg_bytes);
    let hash = Keccak256::digest(&prefixed);

    let (signature, recovery_id) = signing_key
        .sign_prehash_recoverable(&hash)
        .map_err(|e| e.to_string())?;

    // v = 27 ou 28 (convenção Ethereum)
    let v = recovery_id.to_byte() + 27u8;
    let sig_hex = format!("0x{}{:02x}", hex::encode(signature.to_bytes()), v);

    Ok(sig_hex)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_or_create_device_key,
            sign_challenge,
            sign_session_hash,
            vault_key_exists,
            derive_vault_key_from_wallet,
            encrypt_vault_key_for_device,
            vault_list_entries,
            vault_upsert_entry,
            vault_delete_entry,
            vault_list_profiles,
            vault_add_profile,
            vault_rename_profile,
            vault_delete_profile,
            vault_encrypt,
            vault_decrypt,
            vault_publish,
            vault_pending_changes,
            vault_get_providers,
            vault_set_providers,
            vault_get_device_permissions,
            vault_set_device_permission,
            ledger::is_ledger_connected,
            ledger::get_ledger_address,
            ledger::sign_ledger_transaction,
            ledger::sign_ledger_personal_message
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes_gcm::aead::Aead;
    use k256::ecdsa::SigningKey;
    use k256::elliptic_curve::ecdh::diffie_hellman;
    use k256::elliptic_curve::sec1::FromEncodedPoint;
    use k256::PublicKey;
    use rand::rngs::OsRng;

    // Round-trip completo: cifra com encrypt_bytes_for_device (lado Desktop) e
    // decifra reimplementando exatamente o que decryptVaultKeyFromPairing faz
    // no mobile (ECDH + SHA-256 + AES-256-GCM). Existe pra pegar exatamente o
    // bug achado na Sessão 92: a chave AES era o segredo ECDH cru, sem o hash
    // SHA-256 que o mobile sempre esperou — toda vault key entregue via
    // pareamento falhava a decifra com erro de MAC, mesmo com o blob correto
    // on-chain. Sem este teste, o mesmo bug pode voltar (ex: alguém "otimiza"
    // e remove o Sha256::digest de novo) sem que `cargo test` reclame.
    #[test]
    fn encrypt_bytes_for_device_round_trips_with_mobile_side_decryption() {
        let device_priv = SigningKey::random(&mut OsRng);
        let device_pub_hex = hex::encode(
            device_priv
                .verifying_key()
                .to_encoded_point(false) // uncompressed, 65 bytes — mesmo formato que o mobile envia
                .as_bytes(),
        );
        let vault_key = b"0123456789abcdef0123456789abcdef"; // 32 bytes fake vault key

        let blob_b64 = encrypt_bytes_for_device(vault_key, &format!("0x{device_pub_hex}"))
            .expect("encryption should succeed");

        use base64::{engine::general_purpose::STANDARD, Engine as _};
        let blob = STANDARD.decode(blob_b64).expect("valid base64");

        let ephemeral_pub_bytes = &blob[0..33];
        let nonce_bytes = &blob[33..45];
        let ciphertext = &blob[45..];

        let point = k256::EncodedPoint::from_bytes(ephemeral_pub_bytes).expect("valid point");
        let ephemeral_pub = PublicKey::from_encoded_point(&point).unwrap();

        let shared = diffie_hellman(device_priv.as_nonzero_scalar(), ephemeral_pub.as_affine());
        let aes_key_bytes = Sha256::digest(shared.raw_secret_bytes());
        let aes_key = Key::<Aes256Gcm>::from_slice(&aes_key_bytes);
        let cipher = Aes256Gcm::new(aes_key);

        let plaintext = cipher
            .decrypt(nonce_bytes.into(), ciphertext)
            .expect("decryption should succeed with matching SHA-256-derived key");

        assert_eq!(plaintext, vault_key);
    }

    // Vetor cruzado fixo, gerado uma vez rodando o EciesService.encrypt real
    // do Dart (mobile/tool/gen_ecies_vector.dart, descartado depois de gerar
    // este vetor) contra uma chave privada de teste determinística
    // (SHA-256("truthid-ecies-fixed-test-vector-v1")). O mesmo trio
    // {recipientPrivateKeyHex, blobBase64, expectedPlaintextHex} também é
    // usado em `mobile/test/services/ecies_service_test.dart` e em
    // `extension/src/crypto/ecies.test.ts` — os três decifram o mesmo blob e
    // conferem o mesmo plaintext, provando interoperabilidade determinística
    // entre Rust, Dart e JS sem precisar de dois dispositivos reais (fecha o
    // sentido que o teste acima não cobre: o mobile agora também cifra, não
    // só decifra). Achado no caminho, ao gerar este vetor: o
    // `decryptVaultKeyFromPairing` do Dart usava `SecretBox(ciphertext, mac:
    // Mac.empty)` com o tag já concatenado ao ciphertext — o pacote
    // `cryptography` recalcula o MAC sobre o `cipherText` inteiro e nunca
    // bate contra `Mac.empty`, então essa chamada sempre lançava erro de MAC
    // em runtime real. Corrigido no Dart pra usar `SecretBox.fromConcatenation`.
    // A Sessão 92 nunca pegou isso porque o teste Rust de lá reimplementa o
    // decrypt em Rust puro, sem nunca chamar o código Dart de verdade.
    #[test]
    fn dart_produced_blob_decrypts_correctly() {
        let recipient_priv_hex =
            "ebea44b99557c83965e6152a1393a5c6d74fe114f0a626f51bb2349e815136b2";
        let blob_b64 = "AqQAXxG3rw53DVihUXbTzqHcENoLZGbHFsnNHPFvZduk0FF00QwiZMLWLCs8q19CzAj4kYiWXr1jUTn0tUxh1ibNVbwPQiCSBZAJdH1eqE86qT1Na5ytsA==";
        let expected_plaintext_hex =
            "747275746869642d7661756c742d656e7472792d66697874757265";

        use base64::{engine::general_purpose::STANDARD, Engine as _};
        let recipient_priv_bytes = hex::decode(recipient_priv_hex).expect("valid hex");
        let recipient_priv = SigningKey::from_bytes(recipient_priv_bytes.as_slice().into())
            .expect("valid private key");

        let blob = STANDARD.decode(blob_b64).expect("valid base64");
        let ephemeral_pub_bytes = &blob[0..33];
        let nonce_bytes = &blob[33..45];
        let ciphertext = &blob[45..];

        let point = k256::EncodedPoint::from_bytes(ephemeral_pub_bytes).expect("valid point");
        let ephemeral_pub = PublicKey::from_encoded_point(&point).unwrap();

        let shared = diffie_hellman(
            recipient_priv.as_nonzero_scalar(),
            ephemeral_pub.as_affine(),
        );
        let aes_key_bytes = Sha256::digest(shared.raw_secret_bytes());
        let aes_key = Key::<Aes256Gcm>::from_slice(&aes_key_bytes);
        let cipher = Aes256Gcm::new(aes_key);

        let plaintext = cipher
            .decrypt(nonce_bytes.into(), ciphertext)
            .expect("Rust should decrypt a blob produced by the real Dart EciesService.encrypt");

        assert_eq!(hex::encode(&plaintext), expected_plaintext_hex);
    }
}

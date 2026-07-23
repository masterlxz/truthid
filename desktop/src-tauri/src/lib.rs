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

mod backup;
mod bundler;
mod config;
mod ipfs;
mod ledger;
mod local_signer_server;
mod pin;
mod sign_message;
mod sign_request;
mod single_slot_channel;
mod vault;
mod vault_edit;

const SERVICE: &str = "truthid";
const ACCOUNT: &str = "device-private-key";
const VAULT_KEY_ACCOUNT: &str = "vault-key";

/// Caminho de fallback quando o keyring do SO não está disponível (ex: Docker).
/// Usa $HOME/.truthid/device.key — montado como volume no compose para persistir.
fn fallback_key_path() -> Result<std::path::PathBuf, String> {
    crate::config::truthid_dir().map(|d| d.join("device.key"))
}

/// Lê a chave privada do keyring ou do arquivo de fallback.
/// Gera e salva uma nova chave se nenhuma existir.
pub(crate) fn get_device_key_hex() -> Result<String, String> {
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
    crate::config::truthid_dir().map(|d| d.join("vault.key"))
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

/// Assina um hash de 32 bytes já pronto com o prefixo EIP-191 personal_sign
/// (keccak256("\x19Ethereum Signed Message:\n32" + hash)) — o mesmo
/// procedimento que `TruthIDAccount._validateSignature` espera pra
/// reconhecer a device key, seja o hash de uma sessão (`SessionRegistry`)
/// ou de uma UserOperation ERC-4337. Função pura (sem I/O de keyring), pra
/// poder ser testada com uma chave conhecida sem tocar o keyring do SO —
/// `sign_session_hash`/`sign_user_op_hash` (comandos Tauri) só buscam a
/// device key e formatam a saída.
fn sign_eip191_hash_raw(
    priv_bytes: &[u8],
    hash_bytes: &[u8],
) -> Result<(k256::ecdsa::Signature, k256::ecdsa::RecoveryId), String> {
    if hash_bytes.len() != 32 {
        return Err(format!("hash must be 32 bytes, got {}", hash_bytes.len()));
    }
    let signing_key = SigningKey::from_bytes(priv_bytes.into()).map_err(|e| e.to_string())?;

    let prefix = b"\x19Ethereum Signed Message:\n32";
    let mut msg = Vec::with_capacity(prefix.len() + 32);
    msg.extend_from_slice(prefix);
    msg.extend_from_slice(hash_bytes);
    let digest = Keccak256::digest(&msg);

    signing_key
        .sign_prehash_recoverable(&digest)
        .map_err(|e| e.to_string())
}

/// Signs a 32-byte session hash for on-chain createSession.
/// The contract verifies: ecrecover(keccak256("\x19Ethereum Signed Message:\n32" + hash), v, r, s) == devicePubKey
/// Returns (r, s, v) as separate values so the caller can pass them as distinct ABI arguments.
#[tauri::command]
fn sign_session_hash(hash: String) -> Result<(String, String, u8), String> {
    let hash_bytes = hex::decode(hash.trim_start_matches("0x"))
        .map_err(|e| format!("invalid hash hex: {e}"))?;
    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let (signature, recovery_id) = sign_eip191_hash_raw(&priv_bytes, &hash_bytes)?;

    let sig_bytes = signature.to_bytes();
    let r = format!("0x{}", hex::encode(&sig_bytes[..32]));
    let s = format!("0x{}", hex::encode(&sig_bytes[32..]));
    let v = recovery_id.to_byte() + 27u8;

    Ok((r, s, v))
}

/// Assina o hash de uma UserOperation ERC-4337 v0.7 com a device key — mesmo
/// procedimento de `sign_session_hash`, hash de aplicação diferente (dá ao
/// Desktop a mesma capacidade que o Mobile já tem via
/// `DeviceKeyService.signHash`, ver `mobile/lib/services/user_operation_signer.dart`).
/// Devolve a assinatura já concatenada em 65 bytes hex (r||s||v), formato
/// que o campo `signature` da UserOp espera direto, sem re-split do lado TS.
#[tauri::command]
fn sign_user_op_hash(hash: String) -> Result<String, String> {
    let hash_bytes = hex::decode(hash.trim_start_matches("0x"))
        .map_err(|e| format!("invalid hash hex: {e}"))?;
    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let (signature, recovery_id) = sign_eip191_hash_raw(&priv_bytes, &hash_bytes)?;

    let v = recovery_id.to_byte() + 27u8;
    Ok(format!("0x{}{:02x}", hex::encode(signature.to_bytes()), v))
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
    let _guard = vault::lock_vault();
    let mut v = vault::load()?;
    let saved = v.upsert(entry);
    vault::save(&v)?;
    Ok(saved)
}

/// Remove uma entrada do vault pelo id. Persiste em disco.
#[tauri::command]
fn vault_delete_entry(id: String) -> Result<(), String> {
    let _guard = vault::lock_vault();
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
    let _guard = vault::lock_vault();
    let mut v = vault::load()?;
    v.add_profile(&name);
    vault::save(&v)
}

/// Renomeia um perfil e atualiza em cascata as entradas que o usam. Persiste em disco.
#[tauri::command]
fn vault_rename_profile(old_name: String, new_name: String) -> Result<(), String> {
    let _guard = vault::lock_vault();
    let mut v = vault::load()?;
    v.rename_profile(&old_name, &new_name);
    vault::save(&v)
}

/// Remove um perfil e limpa a tag das entradas que o usam. Persiste em disco.
#[tauri::command]
fn vault_delete_profile(name: String) -> Result<(), String> {
    let _guard = vault::lock_vault();
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
    // Decripta do blob já em memória em vez de read()+load() de novo
    let decrypted = vault::decrypt(&encrypted_blob)?;
    let v: vault::Vault = serde_json::from_slice(&decrypted).map_err(|e| e.to_string())?;
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

/// Retorna a config do bundler Pimlico (chave de API + rede) usada pra
/// assinar/enviar UserOperations via device key.
#[tauri::command]
fn get_bundler_config() -> Result<bundler::BundlerConfig, String> {
    Ok(bundler::load_config())
}

/// Salva a config do bundler Pimlico.
#[tauri::command]
fn save_bundler_config(config: bundler::BundlerConfig) -> Result<(), String> {
    bundler::save_config(&config)
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

/// Marca/desmarca uma entrada como favorita. Comando dedicado (não
/// vault_upsert_entry) pra não renovar updated_at só por causa do toggle —
/// mesmo motivo de vault_set_device_permission.
#[tauri::command]
fn vault_set_favorite(id: String, favorite: bool) -> Result<(), String> {
    let _guard = vault::lock_vault();
    let mut v = vault::load()?;
    if !v.set_favorite(&id, favorite) {
        return Err(format!("vault entry not found: {id}"));
    }
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

/// Serializa o vault local inteiro e cifra com uma senha de export (PBKDF2 +
/// AES-256-GCM), independente da vault key derivada da wallet. Retorna o
/// blob completo (magic+salt+iterations+nonce+ciphertext) em Base64 — o
/// frontend só grava esses bytes no arquivo escolhido pelo usuário.
#[tauri::command]
fn vault_export_backup(password: String) -> Result<String, String> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let v = vault::load()?;
    let json = serde_json::to_vec(&v).map_err(|e| e.to_string())?;
    let blob = backup::encrypt(&json, &password)?;
    Ok(STANDARD.encode(blob))
}

/// Decifra um blob de backup (Base64) com a senha de export e sobrescreve o
/// vault local, recifrando com a vault key deste device — a senha de export
/// nunca é usada pro armazenamento local. Não altera a `version` do JSON
/// importado (ver VaultSyncService.sync() no Mobile, que corrige sozinho se
/// a versão importada estiver desatualizada frente à on-chain).
#[tauri::command]
fn vault_import_backup(blob_b64: String, password: String) -> Result<(), String> {
    let _guard = vault::lock_vault();
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let blob = STANDARD.decode(&blob_b64).map_err(|e| e.to_string())?;
    let json = backup::decrypt(&blob, &password)?;
    let imported: vault::Vault = serde_json::from_slice(&json)
        .map_err(|_| "backup file has invalid vault contents".to_string())?;
    vault::save(&imported)
}

/// Núcleo puro de `personal_sign`/EIP-191 pra uma mensagem string arbitrária —
/// separado de `sign_personal_message` pra ser testável com uma chave fixa,
/// sem tocar keyring (mesmo padrão de `sign_eip191_hash_raw`, que já isola a
/// primitiva de assinatura pré-hash da leitura da device key).
pub(crate) fn sign_personal_message_raw(
    priv_bytes: &[u8],
    message: &str,
) -> Result<String, String> {
    let signing_key = SigningKey::from_bytes(priv_bytes.into()).map_err(|e| e.to_string())?;

    // Ethereum personal_sign format: keccak256("\x19Ethereum Signed Message:\n{len}{message}")
    // Matches what viem's recoverMessageAddress() expects on the server side.
    let msg_bytes = message.as_bytes();
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
    Ok(format!("0x{}{:02x}", hex::encode(signature.to_bytes()), v))
}

/// Assina uma mensagem arbitrária com a device key deste desktop. Usada pelo
/// comando `sign_challenge` e injetada em `sign_message::handle_incoming` como
/// a closure `sign` do canal `/truthid/v1/sign-message`.
pub(crate) fn sign_personal_message(message: &str) -> Result<String, String> {
    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    sign_personal_message_raw(&priv_bytes, message)
}

/// Signs a challenge with this desktop's private key.
/// Returns the signature in Ethereum format: 0x + r (32 bytes) + s (32 bytes) + v (1 byte).
#[tauri::command]
fn sign_challenge(challenge: String) -> Result<String, String> {
    sign_personal_message(&challenge)
}

/// Pina `content` nos providers de pinning que o usuário já configurou —
/// injetada em `pin::handle_incoming` como a closure `pin` do canal
/// `/truthid/v1/pin`. Mesma mensagem de erro de `vault_publish` quando não há
/// provider configurado (mesmo caminho de código, mesma UX).
pub(crate) async fn pin_content(
    content: Vec<u8>,
) -> Result<(String, String, Vec<String>, Vec<String>), String> {
    let providers = ipfs::load_providers();
    if providers.is_empty() {
        return Err(
            "nenhum provider de pinning configurado — use vault_set_providers primeiro".to_string(),
        );
    }
    let result = ipfs::pin_vault(&content, &providers).await?;
    Ok((
        result.cid,
        result.content_hash,
        result.providers_ok,
        result.providers_failed,
    ))
}

#[tauri::command]
async fn local_signer_start(
    app: tauri::AppHandle,
    state: tauri::State<'_, local_signer_server::LocalSignerServerState>,
    sign_requests: tauri::State<'_, std::sync::Arc<sign_request::SignRequestState>>,
    sign_messages: tauri::State<'_, std::sync::Arc<sign_message::SignMessageState>>,
    pin_requests: tauri::State<'_, std::sync::Arc<pin::PinState>>,
    vault_edit_requests: tauri::State<'_, std::sync::Arc<vault_edit::VaultEditState>>,
) -> Result<local_signer_server::LocalSignerStatus, String> {
    use tauri::Emitter;
    let sign_request_app = app.clone();
    let sign_message_app = app.clone();
    let pin_app = app.clone();
    let vault_edit_app = app.clone();
    let sign_request_state = sign_requests.inner().clone();
    let sign_message_state = sign_messages.inner().clone();
    let pin_state = pin_requests.inner().clone();
    let vault_edit_state = vault_edit_requests.inner().clone();
    let config = local_signer_server::ServerConfigBuilder::new()
        .sign_request(sign_request_state, move |payload| {
            let _ = sign_request_app.emit("truthid://sign-request", payload);
        })
        .sign_message(sign_message_state, move |payload| {
            let _ = sign_message_app.emit("truthid://sign-message", payload);
        })
        .pin(pin_state, move |payload| {
            let _ = pin_app.emit("truthid://pin", payload);
        })
        .vault_edit(vault_edit_state, move |payload| {
            let _ = vault_edit_app.emit("truthid://vault-edit", payload);
        })
        .build()?;
    local_signer_server::start(&state, config).await
}

#[tauri::command]
async fn local_signer_stop(
    state: tauri::State<'_, local_signer_server::LocalSignerServerState>,
) -> Result<local_signer_server::LocalSignerStatus, String> {
    Ok(local_signer_server::stop(&state).await)
}

#[tauri::command]
async fn local_signer_status(
    state: tauri::State<'_, local_signer_server::LocalSignerServerState>,
) -> Result<local_signer_server::LocalSignerStatus, String> {
    Ok(local_signer_server::status(&state).await)
}

#[tauri::command]
async fn get_pending_sign_request(
    state: tauri::State<'_, std::sync::Arc<sign_request::SignRequestState>>,
) -> Result<Option<sign_request::SignRequestPayload>, String> {
    Ok(sign_request::current(state.inner()).await)
}

#[tauri::command]
async fn respond_to_sign_request(
    id: String,
    decision: sign_request::SignRequestDecision,
    state: tauri::State<'_, std::sync::Arc<sign_request::SignRequestState>>,
) -> Result<(), String> {
    sign_request::resolve(state.inner(), &id, decision).await
}

/// Retorna true se o pedido de assinatura ainda está pendente (não expirou).
/// O frontend consulta isso antes de chamar executeViaUserOp, que gasta gas.
#[tauri::command]
async fn check_sign_request_valid(
    id: String,
    state: tauri::State<'_, std::sync::Arc<sign_request::SignRequestState>>,
) -> Result<bool, String> {
    Ok(sign_request::is_valid(state.inner(), &id).await)
}

#[tauri::command]
async fn get_pending_sign_message(
    state: tauri::State<'_, std::sync::Arc<sign_message::SignMessageState>>,
) -> Result<Option<sign_message::SignMessagePayload>, String> {
    Ok(sign_message::current(state.inner()).await)
}

#[tauri::command]
async fn respond_to_sign_message(
    id: String,
    decision: sign_message::SignMessageDecision,
    state: tauri::State<'_, std::sync::Arc<sign_message::SignMessageState>>,
) -> Result<(), String> {
    sign_message::resolve(state.inner(), &id, decision).await
}

#[tauri::command]
async fn get_pending_pin_request(
    state: tauri::State<'_, std::sync::Arc<pin::PinState>>,
) -> Result<Option<pin::PinApprovalPayload>, String> {
    Ok(pin::current(state.inner()).await)
}

#[tauri::command]
async fn respond_to_pin_request(
    id: String,
    decision: pin::PinDecision,
    state: tauri::State<'_, std::sync::Arc<pin::PinState>>,
) -> Result<(), String> {
    pin::resolve(state.inner(), &id, decision).await
}

#[tauri::command]
async fn get_pending_vault_edit_request(
    state: tauri::State<'_, std::sync::Arc<vault_edit::VaultEditState>>,
) -> Result<Option<vault_edit::VaultEditApprovalPayload>, String> {
    Ok(vault_edit::current(state.inner()).await)
}

#[tauri::command]
async fn respond_to_vault_edit_request(
    id: String,
    decision: vault_edit::VaultEditDecision,
    state: tauri::State<'_, std::sync::Arc<vault_edit::VaultEditState>>,
) -> Result<(), String> {
    vault_edit::resolve(state.inner(), &id, decision).await
}

/// Os 3 comandos abaixo alimentam a tela de Settings de autorizações de
/// pinning por app (fatia 3) — nenhum deles passa pelo protocolo de
/// aprovação/parking, só leem/gravam o arquivo de autorizações direto.
#[tauri::command]
async fn pin_get_authorizations(
    state: tauri::State<'_, std::sync::Arc<pin::PinState>>,
) -> Result<Vec<pin::PinAuthorization>, String> {
    Ok(pin::list_authorizations(state.inner()).await)
}

#[tauri::command]
async fn pin_revoke_authorization(
    app_name: String,
    state: tauri::State<'_, std::sync::Arc<pin::PinState>>,
) -> Result<(), String> {
    pin::revoke_authorization(state.inner(), &app_name).await
}

#[tauri::command]
async fn pin_set_daily_limit(
    app_name: String,
    daily_limit: u32,
    state: tauri::State<'_, std::sync::Arc<pin::PinState>>,
) -> Result<(), String> {
    pin::set_daily_limit(state.inner(), &app_name, daily_limit).await
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(local_signer_server::LocalSignerServerState::default())
        .manage(std::sync::Arc::new(sign_request::SignRequestState::default()))
        .manage(std::sync::Arc::new(sign_message::SignMessageState::default()))
        .manage(std::sync::Arc::new(pin::PinState::default()))
        .manage(std::sync::Arc::new(vault_edit::VaultEditState::default()))
        .setup(|app| {
            // AppHandle (não State) porque a closure/future precisa ser 'static
            // pra rodar em tauri::async_runtime::spawn — um State<'_, T> tomado
            // aqui ficaria preso ao lifetime do `app` desta closure de setup.
            use tauri::{Emitter, Manager};

            // Linux (WebKitGTK) nega todo pedido de permissão do navegador por
            // padrão — sem isso, getUserMedia (scan de QR via webcam) sempre
            // falha com NotAllowedError, mesmo com o usuário nunca tendo visto
            // um prompt. Escopado só pra UserMediaPermissionRequest (câmera/
            // microfone) — qualquer outro tipo (geolocalização, notificação,
            // etc.) devolve `false` e cai no comportamento padrão (negar),
            // sem abrir a porta pra tudo. Ver PROJECT_STATE.md, "QR no TOTP".
            #[cfg(target_os = "linux")]
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.with_webview(|webview| {
                    use webkit2gtk::{glib::ObjectExt, PermissionRequestExt, UserMediaPermissionRequest, WebViewExt};
                    webview.inner().connect_permission_request(|_, request| {
                        if request.is::<UserMediaPermissionRequest>() {
                            request.allow();
                            true
                        } else {
                            false
                        }
                    });
                });
            }

            let handle = app.handle().clone();
            let notify_handle = handle.clone();
            let notify_handle_message = handle.clone();
            let notify_handle_pin = handle.clone();
            let notify_handle_vault_edit = handle.clone();
            tauri::async_runtime::spawn(async move {
                let state = handle.state::<local_signer_server::LocalSignerServerState>();
                let sign_request_state = handle
                    .state::<std::sync::Arc<sign_request::SignRequestState>>()
                    .inner()
                    .clone();
                let sign_message_state = handle
                    .state::<std::sync::Arc<sign_message::SignMessageState>>()
                    .inner()
                    .clone();
                let pin_state = handle
                    .state::<std::sync::Arc<pin::PinState>>()
                    .inner()
                    .clone();
                let vault_edit_state = handle
                    .state::<std::sync::Arc<vault_edit::VaultEditState>>()
                    .inner()
                    .clone();
                let config = local_signer_server::ServerConfigBuilder::new()
                    .sign_request(sign_request_state, move |payload| {
                        let _ = notify_handle.emit("truthid://sign-request", payload);
                    })
                    .sign_message(sign_message_state, move |payload| {
                        let _ = notify_handle_message.emit("truthid://sign-message", payload);
                    })
                    .pin(pin_state, move |payload| {
                        let _ = notify_handle_pin.emit("truthid://pin", payload);
                    })
                    .vault_edit(vault_edit_state, move |payload| {
                        let _ = notify_handle_vault_edit.emit("truthid://vault-edit", payload);
                    })
                    .build()
                    .expect("ServerConfig should build");
                let result = local_signer_server::start(&state, config).await;
                if let Err(e) = result {
                    eprintln!("failed to start local signer server: {e}");
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_or_create_device_key,
            sign_challenge,
            sign_session_hash,
            sign_user_op_hash,
            get_bundler_config,
            save_bundler_config,
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
            vault_export_backup,
            vault_import_backup,
            vault_publish,
            vault_pending_changes,
            vault_get_providers,
            vault_set_providers,
            vault_get_device_permissions,
            vault_set_device_permission,
            vault_set_favorite,
            local_signer_start,
            local_signer_stop,
            local_signer_status,
            get_pending_sign_request,
            respond_to_sign_request,
            check_sign_request_valid,
            get_pending_sign_message,
            respond_to_sign_message,
            get_pending_pin_request,
            respond_to_pin_request,
            pin_get_authorizations,
            pin_revoke_authorization,
            pin_set_daily_limit,
            get_pending_vault_edit_request,
            respond_to_vault_edit_request,
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

    // Vetor cruzado fixo, o mesmo de
    // `mobile/test/services/device_key_signature_vector_test.dart` (chave
    // #0 padrão do Anvil/Hardhat, pública, sem fundos reais) — prova que
    // `sign_eip191_hash_raw` (usada por `sign_session_hash` e
    // `sign_user_op_hash`) produz byte a byte a mesma assinatura que
    // `EthPrivateKey.signPersonalMessageToUint8List` no Dart (que por sua
    // vez já bate com `viem`'s `signMessage`) pro mesmo par (chave, hash).
    #[test]
    fn sign_eip191_hash_raw_matches_known_vector_from_dart_and_viem() {
        let priv_bytes =
            hex::decode("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
                .expect("valid hex");
        let hash_bytes = Keccak256::digest(b"truthid-14.9.4-known-signature-vector");

        let (signature, recovery_id) = sign_eip191_hash_raw(&priv_bytes, &hash_bytes)
            .expect("signing should succeed");
        let v = recovery_id.to_byte() + 27u8;
        let sig_hex = format!("0x{}{:02x}", hex::encode(signature.to_bytes()), v);

        assert_eq!(
            sig_hex,
            "0xc957aeb33d6e8289d733442cf9b44fbafc6c1c07fbb71eef974c724cc087dea\
e0a4be53c6a97b8f41e53559d6327017adcf62341fc176583751ab61f1020f85\
51c"
        );
    }
}

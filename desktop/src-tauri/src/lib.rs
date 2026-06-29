use hkdf::Hkdf;
use k256::ecdsa::SigningKey;
use keyring::Entry;
use rand::rngs::OsRng;
use sha2::Sha256;
use sha3::{Digest, Keccak256};

mod ledger;

const SERVICE: &str = "truthid";
const ACCOUNT: &str = "device-private-key";

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

/// Deriva a chave de criptografia do vault a partir da chave privada do device.
///
/// Usa HKDF-SHA256 (RFC 5869). A chave privada do device é o IKM; o resultado
/// é uma chave AES-256 de 32 bytes usada apenas para cifrar o vault — nunca
/// para assinar nada. Isolamento por propósito: mudar `info` geraria uma chave
/// completamente diferente, mesmo com o mesmo device.
///
/// Nunca exposta via `#[tauri::command]` — fica em memória no processo Rust.
pub(crate) fn derive_vault_key() -> Result<[u8; 32], String> {
    let priv_hex = get_device_key_hex()?;
    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;

    let hk = Hkdf::<Sha256>::new(Some(b"TruthID"), &priv_bytes);
    let mut okm = [0u8; 32];
    hk.expand(b"vault-key-v1", &mut okm)
        .map_err(|_| "HKDF expand failed".to_string())?;
    Ok(okm)
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
            ledger::is_ledger_connected,
            ledger::get_ledger_address,
            ledger::sign_ledger_transaction
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

use k256::ecdsa::SigningKey;
use keyring::Entry;
use rand::rngs::OsRng;
use sha3::{Digest, Keccak256};

mod ledger;

const SERVICE: &str = "truthid";
const ACCOUNT: &str = "device-private-key";

/// Retorna o endereço Ethereum da chave pública deste desktop.
/// Se ainda não existe uma chave, gera e salva no keyring do SO.
#[tauri::command]
fn get_or_create_device_key() -> Result<String, String> {
    let entry = Entry::new(SERVICE, ACCOUNT).map_err(|e| e.to_string())?;

    let priv_hex = match entry.get_password() {
        Ok(hex) => hex,
        Err(_) => {
            // Primeira vez: gera chave secp256k1 (mesmo algoritmo do Ethereum)
            let signing_key = SigningKey::random(&mut OsRng);
            let hex = hex::encode(signing_key.to_bytes());
            entry.set_password(&hex).map_err(|e| e.to_string())?;
            hex
        }
    };

    // Deriva o endereço Ethereum a partir da chave privada
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

/// Assina um challenge com a chave privada deste desktop.
/// Retorna a assinatura em formato Ethereum: 0x + r (32 bytes) + s (32 bytes) + v (1 byte).
#[tauri::command]
fn sign_challenge(challenge: String) -> Result<String, String> {
    let entry = Entry::new(SERVICE, ACCOUNT).map_err(|e| e.to_string())?;

    let priv_hex = entry
        .get_password()
        .map_err(|_| "Chave não encontrada. Chame get_or_create_device_key primeiro.".to_string())?;

    let priv_bytes = hex::decode(&priv_hex).map_err(|e| e.to_string())?;
    let signing_key = SigningKey::from_bytes(priv_bytes.as_slice().into())
        .map_err(|e| e.to_string())?;

    // Hash keccak256 do challenge — compatível com ecrecover do Solidity
    let hash = Keccak256::digest(challenge.as_bytes());

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
            ledger::is_ledger_connected,
            ledger::get_ledger_address
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

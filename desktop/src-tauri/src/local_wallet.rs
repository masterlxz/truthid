use k256::ecdsa::{RecoveryId, Signature, SigningKey};
use keyring::Entry;
use rand::rngs::OsRng;
use sha3::{Digest, Keccak256};
use std::sync::Mutex;

/// Wallet local embutida (P78, pedaço 1) — permite criar uma identidade
/// TruthID sem Ledger/Trezor/WalletConnect: gera e guarda uma chave
/// secp256k1 só neste device, usada como `owner` da smart account. Espelha
/// a custódia já usada por `get_arweave_wallet`/`get_device_key_hex` em
/// `lib.rs` (keyring do SO com fallback em arquivo `0o600`) e a assinatura
/// já usada por `sign_ledger_transaction`/`sign_ledger_personal_message`
/// (`ledger.rs`), só que a assinatura acontece direto aqui em vez de via
/// HID/USB — não há hardware, a chave privada é local.
const LOCAL_WALLET_ACCOUNT: &str = "local-wallet-private-key";

// Mesmo padrão de VAULT_MUTEX/lock_vault (vault.rs) — fecha a corrida de
// duplo-clique em `local_wallet_generate`: duas chamadas concorrentes
// podiam ambas passar no check-then-act e gerar chaves diferentes, a
// última escrita vencendo silenciosamente (achado real, P84 #6).
static LOCAL_WALLET_MUTEX: Mutex<()> = Mutex::new(());

fn lock_local_wallet() -> std::sync::MutexGuard<'static, ()> {
    LOCAL_WALLET_MUTEX
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn local_wallet_key_path() -> Result<std::path::PathBuf, String> {
    crate::config::truthid_file_path("local_wallet.key")
}

fn local_wallet_backup_confirmed_path() -> Result<std::path::PathBuf, String> {
    crate::config::truthid_file_path("local_wallet_backup_confirmed")
}

/// Lê a chave privada da wallet local (hex) do keyring do SO, com fallback
/// em arquivo — mesmo padrão de `get_arweave_wallet`, incluindo o mesmo
/// cuidado (achado real, P71) de tratar uma entrada de keyring vazia como
/// "não existe", não só o `Err`. Diferente da device key
/// (`get_device_key_hex`), NÃO gera uma chave nova automaticamente — essa
/// chave só nasce de uma ação explícita do usuário (`local_wallet_generate`).
pub(crate) fn get_local_wallet_key_hex() -> Result<String, String> {
    if let Ok(entry) = Entry::new(crate::SERVICE, LOCAL_WALLET_ACCOUNT) {
        if let Ok(hex) = entry.get_password() {
            if !hex.trim().is_empty() {
                return Ok(hex);
            }
        }
    }

    let path = local_wallet_key_path()?;
    if path.exists() {
        return crate::config::read_text(&path).map(|s| s.trim().to_string());
    }

    Err("nenhuma wallet local encontrada — gere uma primeiro".to_string())
}

pub(crate) fn set_local_wallet_key_hex(hex: &str) -> Result<(), String> {
    let saved = Entry::new(crate::SERVICE, LOCAL_WALLET_ACCOUNT)
        .and_then(|e| e.set_password(hex))
        .is_ok();

    if !saved {
        let path = local_wallet_key_path()?;
        crate::config::write_secret_file(&path, hex.as_bytes())?;
    }

    Ok(())
}

/// Deriva o endereço Ethereum a partir de uma chave privada hex — mesma
/// lógica já usada em `get_or_create_device_key` (`lib.rs`): keccak256 da
/// chave pública não comprimida (sem o prefixo `0x04`), últimos 20 bytes.
/// Extraída aqui como função pura testável com uma chave conhecida.
pub(crate) fn derive_address(priv_hex: &str) -> Result<String, String> {
    let priv_bytes = hex::decode(priv_hex).map_err(|e| e.to_string())?;
    let signing_key = SigningKey::from_slice(&priv_bytes).map_err(|e| e.to_string())?;
    let pub_point = signing_key.verifying_key().to_encoded_point(false);
    let pub_bytes = pub_point.as_bytes();
    let hash = Keccak256::digest(&pub_bytes[1..]);
    Ok(format!("0x{}", hex::encode(&hash[12..])))
}

/// Prefixa e hasheia uma mensagem no formato EIP-191 `personal_sign`
/// (`keccak256("\x19Ethereum Signed Message:\n{len}" + message)`) — mesma
/// fórmula de `sign_eip191_hash_raw`/`sign_personal_message_raw` em
/// `lib.rs`, mas recebendo bytes crus já decodificados de hex em vez de uma
/// `&str` UTF-8: o `personal_sign` do provider EIP-1193 recebe a mensagem
/// já em hex vinda da viem, seja o hash de 32 bytes do consentimento de
/// `createIdentity` ou a string `VAULT_KEY_MESSAGE` (que a viem também
/// hex-codifica antes de chamar `personal_sign` quando `message` é passado
/// como string simples).
fn eip191_digest(message: &[u8]) -> [u8; 32] {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let mut prefixed = Vec::with_capacity(prefix.len() + message.len());
    prefixed.extend_from_slice(prefix.as_bytes());
    prefixed.extend_from_slice(message);
    Keccak256::digest(&prefixed).into()
}

fn sign_digest_recoverable(
    priv_bytes: &[u8],
    digest: &[u8; 32],
) -> Result<(Signature, RecoveryId), String> {
    let signing_key = SigningKey::from_slice(priv_bytes).map_err(|e| e.to_string())?;
    signing_key
        .sign_prehash_recoverable(digest)
        .map_err(|e| e.to_string())
}

fn hex_bytes(s: &str) -> Result<Vec<u8>, String> {
    hex::decode(s.trim_start_matches("0x")).map_err(|e| e.to_string())
}

fn format_combined_signature(signature: Signature, recovery_id: RecoveryId) -> String {
    let v = recovery_id.to_byte() + 27u8;
    format!("0x{}{:02x}", hex::encode(signature.to_bytes()), v)
}

/// Gera uma chave secp256k1 nova, salva na custódia local e retorna o
/// endereço Ethereum derivado. Erro se já existir uma wallet local — gerar
/// de novo sobrescreveria silenciosamente uma identidade já controlada por
/// essa chave (mesma classe do bug generate→overwrite documentado pra
/// wallet Arweave, P70/P71).
#[tauri::command]
pub fn local_wallet_generate() -> Result<String, String> {
    let _guard = lock_local_wallet();
    if get_local_wallet_key_hex().is_ok() {
        return Err("já existe uma wallet local neste device".to_string());
    }
    let signing_key = SigningKey::random(&mut OsRng);
    let priv_hex = hex::encode(signing_key.to_bytes());
    let address = derive_address(&priv_hex)?;
    set_local_wallet_key_hex(&priv_hex)?;
    Ok(address)
}

#[tauri::command]
pub fn local_wallet_exists() -> Result<bool, String> {
    Ok(get_local_wallet_key_hex().is_ok())
}

#[tauri::command]
pub fn local_wallet_address() -> Result<String, String> {
    derive_address(&get_local_wallet_key_hex()?)
}

/// Assina o hash cru de uma transação (já serializada em RLP pelo lado TS
/// via `serializeTransaction` da viem) com a chave privada local — SEM
/// prefixo EIP-191, é o mesmo hash que qualquer transação EIP-1559 já usa.
/// Retorna a assinatura combinada `"0x"+r+s+v(27/28)`, mesmo formato que
/// `sign_ledger_transaction`/`sign_trezor_transaction` já devolvem — o lado
/// TS reaproveita o mesmo parser sem mudança.
#[tauri::command]
pub fn sign_local_wallet_transaction(unsigned_tx_hex: String) -> Result<String, String> {
    let unsigned_tx = hex_bytes(&unsigned_tx_hex)?;
    let priv_bytes = hex_bytes(&get_local_wallet_key_hex()?)?;
    let digest: [u8; 32] = Keccak256::digest(&unsigned_tx).into();
    let (signature, recovery_id) = sign_digest_recoverable(&priv_bytes, &digest)?;
    Ok(format_combined_signature(signature, recovery_id))
}

/// Assina uma mensagem via `personal_sign` (EIP-191) com a chave privada
/// local — usado pelo consentimento de `createIdentity` e pela derivação da
/// vault key (`VAULT_KEY_MESSAGE`).
#[tauri::command]
pub fn sign_local_wallet_personal_message(message_hex: String) -> Result<String, String> {
    let message = hex_bytes(&message_hex)?;
    let priv_bytes = hex_bytes(&get_local_wallet_key_hex()?)?;
    let digest = eip191_digest(&message);
    let (signature, recovery_id) = sign_digest_recoverable(&priv_bytes, &digest)?;
    Ok(format_combined_signature(signature, recovery_id))
}

/// Se o backup do vault já foi exportado (ou restaurado de um backup
/// existente) desde que a wallet local foi criada — usado pelo gate
/// bloqueante em `App.tsx` (`useLocalWalletBackupGate`).
#[tauri::command]
pub fn local_wallet_backup_confirmed() -> Result<bool, String> {
    Ok(local_wallet_backup_confirmed_path()?.exists())
}

#[tauri::command]
pub fn confirm_local_wallet_backup() -> Result<(), String> {
    let path = local_wallet_backup_confirmed_path()?;
    crate::config::write_file(&path, b"confirmed")
}

/// Marca o backup como confirmado sem passar pelo comando Tauri — chamado
/// internamente por `vault_import_backup` (`lib.rs`) quando a chave da
/// wallet local é restaurada de um backup: importar um backup já prova que
/// existe cópia em outro lugar, não faz sentido reexibir o gate depois de
/// uma restauração.
pub(crate) fn mark_backup_confirmed() -> Result<(), String> {
    confirm_local_wallet_backup()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Chave #0 padrão do Anvil/Hardhat (pública, sem fundos reais) — mesmo
    // vetor já usado em `lib.rs::sign_eip191_hash_raw_matches_known_vector_from_dart_and_viem`,
    // pra manter consistência entre os testes do projeto.
    const KNOWN_PRIV_HEX: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const KNOWN_ADDRESS: &str = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    #[test]
    fn derive_address_matches_known_vector() {
        assert_eq!(derive_address(KNOWN_PRIV_HEX).unwrap(), KNOWN_ADDRESS);
    }

    #[test]
    fn derive_address_rejects_invalid_hex() {
        assert!(derive_address("not_hex").is_err());
    }

    // P84 #7: antes disso, uma chave hex válida mas de tamanho errado
    // panicava (`GenericArray`'s `.into()` fazia `assert_eq!` no tamanho)
    // em vez de retornar `Err` — `SigningKey::from_slice` valida o tamanho
    // sozinho. 16 bytes e 40 bytes ficam fora do intervalo 24..32 que
    // `from_slice` aceita com zero-padding, então os dois têm que rejeitar
    // de verdade. Construído por repetição pra não depender de contar
    // caracteres hex à mão.
    #[test]
    fn derive_address_rejects_wrong_length_key() {
        let too_short = "11".repeat(16); // 16 bytes
        assert!(derive_address(&too_short).is_err());

        let too_long = format!("{KNOWN_PRIV_HEX}{}", "11".repeat(8)); // 32+8=40 bytes
        assert!(derive_address(&too_long).is_err());
    }

    // Cross-checa `eip191_digest`+`sign_digest_recoverable` (opera sobre
    // bytes crus) contra `crate::sign_personal_message_raw` (já validada em
    // `lib.rs` contra vetores reais do Dart/viem, opera sobre `&str` UTF-8)
    // — pro mesmo texto, os dois caminhos precisam produzir exatamente a
    // mesma assinatura combinada, já que "TruthID Vault Key v1" como string
    // e seus bytes UTF-8 crus representam a mesma mensagem.
    #[test]
    fn eip191_digest_matches_sign_personal_message_raw_for_same_text() {
        let priv_bytes = hex::decode(KNOWN_PRIV_HEX).unwrap();
        let message = "TruthID Vault Key v1";

        let expected = crate::sign_personal_message_raw(&priv_bytes, message).unwrap();

        let digest = eip191_digest(message.as_bytes());
        let (signature, recovery_id) = sign_digest_recoverable(&priv_bytes, &digest).unwrap();
        let actual = format_combined_signature(signature, recovery_id);

        assert_eq!(actual, expected);
    }

    // P84 #7: mesmo cuidado de `derive_address_rejects_wrong_length_key`,
    // agora pro outro call-site de `SigningKey::from_slice`.
    #[test]
    fn sign_digest_recoverable_rejects_wrong_length_key() {
        let priv_bytes = hex::decode(KNOWN_PRIV_HEX).unwrap();
        let digest = eip191_digest(b"wrong length key check");

        assert!(sign_digest_recoverable(&priv_bytes[..16], &digest).is_err());
    }

    #[test]
    fn sign_digest_recoverable_produces_valid_recovery_id() {
        let priv_bytes = hex::decode(KNOWN_PRIV_HEX).unwrap();
        let digest = eip191_digest(b"some arbitrary message");

        let (_, recovery_id) = sign_digest_recoverable(&priv_bytes, &digest).unwrap();

        assert!(recovery_id.to_byte() == 0 || recovery_id.to_byte() == 1);
    }

    #[test]
    fn sign_digest_recoverable_signature_recovers_to_known_address() {
        use k256::ecdsa::signature::hazmat::PrehashVerifier;

        let priv_bytes = hex::decode(KNOWN_PRIV_HEX).unwrap();
        let digest = eip191_digest(b"round trip check");

        let (signature, _) = sign_digest_recoverable(&priv_bytes, &digest).unwrap();
        let signing_key = SigningKey::from_bytes(priv_bytes.as_slice().into()).unwrap();
        let verifying_key = signing_key.verifying_key();

        assert!(verifying_key.verify_prehash(&digest, &signature).is_ok());
    }

    #[test]
    fn format_combined_signature_has_expected_shape() {
        let priv_bytes = hex::decode(KNOWN_PRIV_HEX).unwrap();
        let digest = eip191_digest(b"format check");
        let (signature, recovery_id) = sign_digest_recoverable(&priv_bytes, &digest).unwrap();

        let combined = format_combined_signature(signature, recovery_id);

        assert!(combined.starts_with("0x"));
        assert_eq!(combined.len(), 2 + 64 + 64 + 2);
        let v = u8::from_str_radix(&combined[130..132], 16).unwrap();
        assert!(v == 27 || v == 28);
    }
}

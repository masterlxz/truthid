use keyring::Entry;

/// Bloqueio opcional do app por senha própria do TruthID — pedido direto do
/// dono do projeto (não integração com biometria/PIN do SO: pesquisado, não
/// existe hoje um plugin Tauri maduro cobrindo Windows Hello/Touch ID/Linux
/// de forma uniforme, e nem daria pra validar nesta máquina, que é Linux).
/// Mesmo espírito do bloqueio do Mobile (`AppLockService`/`SecurityScreen`),
/// mas aqui a senha é o próprio mecanismo, não um delegado do SO.
///
/// Reaproveita `backup::encrypt`/`backup::decrypt` (PBKDF2-HMAC-SHA256 +
/// AES-256-GCM, já testado no backup exportável do Vault) em vez de escrever
/// hash-and-compare novo: a senha cifra um marcador fixo conhecido;
/// "verificar a senha" é só tentar decifrar — o tag de autenticação do GCM
/// já rejeita senha errada sozinho.
const APP_LOCK_ACCOUNT: &str = "app-lock-verifier";
const APP_LOCK_MARKER: &[u8] = b"TRUTHID_APP_LOCK_V1";

fn app_lock_blob_path() -> Result<std::path::PathBuf, String> {
    crate::config::truthid_file_path("app_lock.enc")
}

/// Núcleo puro testável — opera só sobre o blob recebido, sem tocar
/// keyring/arquivo (mesmo princípio de `backup::encrypt_with` e das funções
/// puras de `local_wallet.rs`, ex. `derive_address`/`eip191_digest`).
fn create_blob(password: &str) -> Result<Vec<u8>, String> {
    crate::backup::encrypt(APP_LOCK_MARKER, password)
}

fn verify_blob(blob: &[u8], password: &str) -> bool {
    match crate::backup::decrypt(blob, password) {
        Ok(plaintext) => plaintext == APP_LOCK_MARKER,
        Err(_) => false,
    }
}

/// Lê o blob cifrado (hex) do keyring do SO, com fallback em arquivo — mesmo
/// padrão de `local_wallet::get_local_wallet_key_hex`, incluindo o mesmo
/// cuidado (P71) de tratar uma entrada de keyring vazia como "não existe".
fn get_app_lock_blob_hex() -> Result<String, String> {
    if let Ok(entry) = Entry::new(crate::SERVICE, APP_LOCK_ACCOUNT) {
        if let Ok(hex) = entry.get_password() {
            if !hex.trim().is_empty() {
                return Ok(hex);
            }
        }
    }

    let path = app_lock_blob_path()?;
    if path.exists() {
        return crate::config::read_text(&path).map(|s| s.trim().to_string());
    }

    Err("bloqueio do app não está habilitado".to_string())
}

fn set_app_lock_blob_hex(hex: &str) -> Result<(), String> {
    let saved = Entry::new(crate::SERVICE, APP_LOCK_ACCOUNT)
        .and_then(|e| e.set_password(hex))
        .is_ok();

    if !saved {
        let path = app_lock_blob_path()?;
        crate::config::write_secret_file(&path, hex.as_bytes())?;
    }

    Ok(())
}

fn clear_app_lock_blob() -> Result<(), String> {
    let _ = Entry::new(crate::SERVICE, APP_LOCK_ACCOUNT).and_then(|e| e.delete_password());

    let path = app_lock_blob_path()?;
    if path.exists() {
        std::fs::remove_file(&path).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn app_lock_is_enabled() -> Result<bool, String> {
    Ok(get_app_lock_blob_hex().is_ok())
}

/// Habilita o bloqueio com uma senha nova. Recusa se já houver um habilitado
/// — mesmo princípio anti-overwrite-silencioso de `local_wallet_generate`
/// (trocar a senha exige desabilitar com a senha atual primeiro).
#[tauri::command]
pub fn app_lock_enable(password: String) -> Result<(), String> {
    if get_app_lock_blob_hex().is_ok() {
        return Err("bloqueio do app já está habilitado".to_string());
    }
    let blob = create_blob(&password)?;
    set_app_lock_blob_hex(&hex::encode(blob))
}

/// Verifica uma senha contra o blob armazenado. Senha errada retorna
/// `Ok(false)`, não `Err` — é uma resposta de UI esperada, não uma exceção.
#[tauri::command]
pub fn app_lock_verify(password: String) -> Result<bool, String> {
    let hex_blob = match get_app_lock_blob_hex() {
        Ok(h) => h,
        Err(_) => return Ok(false),
    };
    let blob = hex::decode(hex_blob).map_err(|e| e.to_string())?;
    Ok(verify_blob(&blob, &password))
}

/// Desabilita o bloqueio — exige a senha atual: diferente do Mobile (onde o
/// próprio SO já barrou a entrada no app antes de chegar nas Configurações),
/// aqui a senha é o único gate, então desabilitar sem confirmá-la anularia a
/// proteção sem nenhuma fricção.
#[tauri::command]
pub fn app_lock_disable(password: String) -> Result<(), String> {
    if !app_lock_verify(password)? {
        return Err("senha incorreta".to_string());
    }
    clear_app_lock_blob()
}

/// Reseta o bloqueio sem exigir a senha atual — único jeito de recuperar
/// acesso ao app se a senha foi esquecida ou o blob armazenado está
/// corrompido (`app_lock_verify` rejeitando em vez de resolver `false`).
/// Sem confirmação criptográfica por design: não há senha alternativa pra
/// checar. Só remove o gate de abertura do app — não toca no Vault nem em
/// nenhuma outra credencial.
#[tauri::command]
pub fn app_lock_reset() -> Result<(), String> {
    clear_app_lock_blob()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verify_blob_accepts_correct_password() {
        let blob = create_blob("hunter2").unwrap();
        assert!(verify_blob(&blob, "hunter2"));
    }

    #[test]
    fn verify_blob_rejects_wrong_password() {
        let blob = create_blob("correct-password").unwrap();
        assert!(!verify_blob(&blob, "wrong-password"));
    }

    #[test]
    fn verify_blob_rejects_garbage() {
        assert!(!verify_blob(b"not a valid backup blob", "anything"));
    }

    #[test]
    fn different_passwords_produce_non_interchangeable_blobs() {
        let blob_a = create_blob("password-a").unwrap();
        assert!(!verify_blob(&blob_a, "password-b"));
    }
}

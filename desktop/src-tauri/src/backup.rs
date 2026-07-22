// Backup criptografado exportável do Vault (item 4 do roadmap pós-Fase 14).
//
// Diferente do resto do Vault (chave sempre derivada da assinatura da
// wallet, nunca uma senha), o backup usa uma senha de exportação separada,
// escolhida explicitamente pelo dono do projeto em vez de reaproveitar a
// vault key — restaurar um backup não deve exigir ter a wallet em mãos.
//
// Formato do envelope: magic(8) || salt(16) || kdf_iterations(4, big-endian
// u32) || nonce(12) || ciphertext+tag(AES-256-GCM). O iteration count viaja
// dentro do arquivo (não fixo na hora de decifrar) pra poder aumentar o
// padrão no futuro sem quebrar backups antigos.

use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use rand::RngCore;
use sha2::Sha256;

pub(crate) const BACKUP_MAGIC: &[u8; 8] = b"TIDVLTB1";
// Recomendação atual da OWASP Password Storage Cheat Sheet pra PBKDF2-HMAC-SHA256.
pub(crate) const BACKUP_KDF_ITERATIONS: u32 = 600_000;
pub(crate) const BACKUP_MAX_KDF_ITERATIONS: u32 = 10_000_000;

const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;
const HEADER_LEN: usize = 8 + SALT_LEN + 4 + NONCE_LEN; // magic+salt+iterations+nonce

fn derive_key(password: &str, salt: &[u8], iterations: u32) -> [u8; 32] {
    let mut key = [0u8; 32];
    pbkdf2::pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, iterations, &mut key);
    key
}

// Núcleo testável — caller fornece salt/nonce/iterations explicitamente.
// Produção usa `encrypt()` (aleatório); o vetor fixo cruzado com o Dart chama
// isto direto com valores hardcoded e um iteration count baixo (rápido pro
// teste, nunca usado em produção).
fn encrypt_with(
    plaintext: &[u8],
    password: &str,
    salt: [u8; SALT_LEN],
    iterations: u32,
    nonce_bytes: [u8; NONCE_LEN],
) -> Result<Vec<u8>, String> {
    let key_bytes = derive_key(password, &salt, iterations);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&key_bytes));
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|_| "backup encrypt failed".to_string())?;

    let mut blob = Vec::with_capacity(HEADER_LEN + ciphertext.len());
    blob.extend_from_slice(BACKUP_MAGIC);
    blob.extend_from_slice(&salt);
    blob.extend_from_slice(&iterations.to_be_bytes());
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ciphertext);
    Ok(blob)
}

pub(crate) fn encrypt(plaintext: &[u8], password: &str) -> Result<Vec<u8>, String> {
    let mut salt = [0u8; SALT_LEN];
    rand::rngs::OsRng.fill_bytes(&mut salt);
    let nonce_bytes: [u8; NONCE_LEN] = Aes256Gcm::generate_nonce(&mut OsRng).into();
    encrypt_with(plaintext, password, salt, BACKUP_KDF_ITERATIONS, nonce_bytes)
}

pub(crate) fn decrypt(blob: &[u8], password: &str) -> Result<Vec<u8>, String> {
    if blob.len() < HEADER_LEN + 16 {
        return Err("backup file too short or corrupted".to_string());
    }
    if &blob[0..8] != BACKUP_MAGIC {
        return Err("not a TruthID backup file (bad magic)".to_string());
    }
    let salt = &blob[8..8 + SALT_LEN];
    let iterations = u32::from_be_bytes(blob[8 + SALT_LEN..HEADER_LEN - NONCE_LEN].try_into().unwrap());
    if iterations > BACKUP_MAX_KDF_ITERATIONS {
        return Err(format!(
            "backup file has excessive KDF iterations ({iterations}); max is {BACKUP_MAX_KDF_ITERATIONS}"
        ));
    }
    let nonce = Nonce::from_slice(&blob[HEADER_LEN - NONCE_LEN..HEADER_LEN]);

    let key_bytes = derive_key(password, salt, iterations);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&key_bytes));
    cipher
        .decrypt(nonce, &blob[HEADER_LEN..])
        .map_err(|_| "wrong password or corrupted backup file".to_string())
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_empty() {
        let blob = encrypt(b"", "hunter2").unwrap();
        let plain = decrypt(&blob, "hunter2").unwrap();
        assert_eq!(plain, b"");
    }

    #[test]
    fn roundtrip_json() {
        let original = br#"{"version":1,"entries":[{"site":"github.com"}]}"#;
        let blob = encrypt(original, "correct horse battery staple").unwrap();
        let plain = decrypt(&blob, "correct horse battery staple").unwrap();
        assert_eq!(plain, original);
    }

    #[test]
    fn wrong_password_fails() {
        let blob = encrypt(b"sensitive", "senha-certa").unwrap();
        assert!(decrypt(&blob, "senha-errada").is_err());
    }

    #[test]
    fn tampered_ciphertext_fails() {
        let mut blob = encrypt(b"sensitive", "hunter2").unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0xFF;
        assert!(decrypt(&blob, "hunter2").is_err());
    }

    #[test]
    fn bad_magic_fails() {
        let mut blob = encrypt(b"sensitive", "hunter2").unwrap();
        blob[0] ^= 0xFF;
        let err = decrypt(&blob, "hunter2").unwrap_err();
        assert!(err.contains("bad magic"), "erro inesperado: {err}");
    }

    #[test]
    fn blob_too_short_fails() {
        assert!(decrypt(&[0u8; 10], "hunter2").is_err());
    }

    #[test]
    fn different_salt_nonce_each_call() {
        let blob1 = encrypt(b"same", "hunter2").unwrap();
        let blob2 = encrypt(b"same", "hunter2").unwrap();
        assert_ne!(blob1, blob2);
        assert_eq!(decrypt(&blob1, "hunter2").unwrap(), b"same");
        assert_eq!(decrypt(&blob2, "hunter2").unwrap(), b"same");
    }

    // Vetor fixo cruzado byte-a-byte com
    // mobile/test/services/backup_cipher_service_test.dart — mesma senha,
    // salt, iterations (baixo de propósito, só pra teste) e nonce dos dois
    // lados. Prova que os dois lados produzem exatamente o mesmo blob.
    #[test]
    fn fixed_vector_matches_dart() {
        let password = "cross-language-test-vector";
        let salt: [u8; SALT_LEN] = [
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
            0x0f, 0x10,
        ];
        let nonce: [u8; NONCE_LEN] = [0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b];
        let iterations = 100u32;
        let plaintext = b"{\"version\":1,\"entries\":[]}";

        let blob = encrypt_with(plaintext, password, salt, iterations, nonce).unwrap();
        assert_eq!(
            hex::encode(&blob),
            "544944564c5442310102030405060708090a0b0c0d0e0f1000000064202122232425262728292a2b\
             4aa17c8e8b6eefe955e8f4e0d999dec4058c226c174dbc07c671120e5225cd39d4910240919fe9d309a9"
        );
    }

    #[test]
    fn excessive_iterations_rejected() {
        let mut blob = encrypt(b"data", "hunter2").unwrap();
        blob[8 + SALT_LEN..8 + SALT_LEN + 4]
            .copy_from_slice(&u32::MAX.to_be_bytes());
        assert!(decrypt(&blob, "hunter2").is_err());
    }
}

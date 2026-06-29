use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};

use crate::derive_vault_key;

// Formato do blob: nonce(12) || ciphertext+tag(n+16)
// O nonce é gerado aleatoriamente a cada chamada — nunca reutilizado.

pub(crate) fn encrypt(plaintext: &[u8]) -> Result<Vec<u8>, String> {
    let key_bytes = derive_vault_key()?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);

    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|_| "vault encrypt failed".to_string())?;

    let mut blob = Vec::with_capacity(12 + ciphertext.len());
    blob.extend_from_slice(&nonce);
    blob.extend_from_slice(&ciphertext);
    Ok(blob)
}

pub(crate) fn decrypt(blob: &[u8]) -> Result<Vec<u8>, String> {
    // mínimo: 12 bytes de nonce + 16 bytes de tag GCM
    if blob.len() < 28 {
        return Err("vault blob too short".to_string());
    }
    let key_bytes = derive_vault_key()?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);

    let nonce = Nonce::from_slice(&blob[..12]);
    cipher
        .decrypt(nonce, &blob[12..])
        .map_err(|_| "vault decrypt failed — blob corrupted or wrong key".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_empty() {
        let blob = encrypt(b"").unwrap();
        let plain = decrypt(&blob).unwrap();
        assert_eq!(plain, b"");
    }

    #[test]
    fn roundtrip_json() {
        let original = br#"{"site":"github.com","user":"fab","password":"s3cr3t"}"#;
        let blob = encrypt(original).unwrap();
        let plain = decrypt(&blob).unwrap();
        assert_eq!(plain, original);
    }

    #[test]
    fn different_nonce_each_call() {
        let blob1 = encrypt(b"same").unwrap();
        let blob2 = encrypt(b"same").unwrap();
        // Blobs distintos (nonce aleatório), mesmo plaintext
        assert_ne!(blob1, blob2);
        // Mas ambos decifram corretamente
        assert_eq!(decrypt(&blob1).unwrap(), b"same");
        assert_eq!(decrypt(&blob2).unwrap(), b"same");
    }

    #[test]
    fn tampered_blob_fails() {
        let mut blob = encrypt(b"sensitive").unwrap();
        blob[15] ^= 0xFF; // corrompe um byte
        assert!(decrypt(&blob).is_err());
    }

    #[test]
    fn blob_too_short_fails() {
        assert!(decrypt(&[0u8; 10]).is_err());
    }
}

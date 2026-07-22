use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

use crate::{get_vault_key, derive_vault_key_legacy};

// ---------------------------------------------------------------------------
// Tipos de dados
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct VaultEntry {
    pub id: String,
    pub site: String,
    pub url: String,
    pub username: String,
    pub password: String,
    pub notes: String,
    /// Lista de grupos a que esta entrada pertence (ex: ["Trabalho", "Casa"]).
    #[serde(default)]
    pub profiles: Vec<String>,
    /// Campo legado — só lido na desserialização para migração. Nunca escrito.
    #[serde(default, skip_serializing)]
    profile: String,
    /// Segredo TOTP (RFC 6238) em base32, se o usuário configurou 2FA pra essa
    /// entrada. Cálculo do código acontece em TS/Dart, não no Rust — este
    /// campo nunca deve ser incluído no payload enviado à extensão de
    /// navegador (ver vault_session_screen.dart no Mobile).
    #[serde(default)]
    pub totp_secret: Option<String>,
    /// Credencial WebAuthn (passkey) da entrada, se o usuário gerou uma. Só
    /// existe (Some) se o usuário clicou em "Gerar passkey" — a chave privada
    /// nunca é manipulada aqui, só armazenada como bytes opacos; toda a
    /// cerimônia WebAuthn (keygen, CBOR/COSE, atestação, assinatura) acontece
    /// em TS/Dart, nunca no Rust (mesma regra do totp_secret). Este campo
    /// nunca deve ser incluído no payload enviado à extensão de navegador.
    #[serde(default)]
    pub passkey: Option<Passkey>,
    /// Favorito — sincroniza entre devices como qualquer outro campo do
    /// Vault (não é preferência local). Trocado via `Vault::set_favorite`,
    /// não via `upsert`, pra não renovar `updated_at` só por causa do toggle.
    #[serde(default)]
    pub favorite: bool,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct Passkey {
    pub rp_id: String,
    pub credential_id_b64: String,
    pub user_handle_b64: String,
    pub private_key_hex: String,
    pub sign_count: u32,
    pub created_at: u64,
}

/// Permissão de escrita no vault por device (`pub_key` = endereço do device).
/// Concedida só pelo controller (Desktop/Ledger) — devices nunca concedem a
/// si mesmos nem a outros. Trava de UX, não é imposta pelo contrato (não há
/// terceiros desconfiados — ver VaultRegistry.sol e PROJECT_STATE.md, 13.7).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct DeviceVaultPermission {
    pub pub_key: String,
    pub can_write: bool,
}

#[derive(Serialize, Deserialize, Default, Debug)]
pub(crate) struct Vault {
    pub version: u64,
    pub entries: Vec<VaultEntry>,
    /// Nomes de perfis criados pelo usuário (ex: ["Trabalho", "Banco"]). Livre,
    /// não é mais uma lista fixa — ver PROJECT_STATE.md, Sessão 97.
    #[serde(default)]
    pub profile_names: Vec<String>,
    /// Permissões de escrita por device — movido do arquivo local
    /// `vault_permissions.json` (Sessão 97) pra viajar dentro do blob
    /// sincronizado, permitindo o Mobile ler sua própria permissão.
    #[serde(default)]
    pub device_permissions: Vec<DeviceVaultPermission>,
}

impl Vault {
    // Cria (id vazio) ou atualiza (id existente) uma entrada.
    // Incrementa version e atualiza updated_at em qualquer caso.
    pub(crate) fn upsert(&mut self, mut entry: VaultEntry) -> VaultEntry {
        let now = now_secs();
        self.version += 1;

        if entry.id.is_empty() {
            // Nova entrada
            entry.id = new_id();
            entry.created_at = now;
            entry.updated_at = now;
            self.entries.push(entry.clone());
        } else if let Some(existing) = self.entries.iter_mut().find(|e| e.id == entry.id) {
            // Atualização: preserva created_at, renova updated_at
            entry.created_at = existing.created_at;
            entry.updated_at = now;
            *existing = entry.clone();
        } else {
            // id fornecido mas não encontrado — trata como nova entrada com esse id
            entry.created_at = now;
            entry.updated_at = now;
            self.entries.push(entry.clone());
        }

        entry
    }

    // Remove entrada pelo id. Retorna true se encontrou e removeu.
    pub(crate) fn delete(&mut self, id: &str) -> bool {
        let before = self.entries.len();
        self.entries.retain(|e| e.id != id);
        let removed = self.entries.len() < before;
        if removed {
            self.version += 1;
        }
        removed
    }

    // Cria um novo perfil (nome livre, sem duplicatas). No-op se já existir.
    pub(crate) fn add_profile(&mut self, name: &str) {
        if !self.profile_names.iter().any(|p| p == name) {
            self.profile_names.push(name.to_string());
            self.version += 1;
        }
    }

    // Renomeia um perfil na lista e em cascata em todas as entradas que o usam.
    // Retorna false se `old` não existir na lista.
    pub(crate) fn rename_profile(&mut self, old: &str, new: &str) -> bool {
        let Some(slot) = self.profile_names.iter_mut().find(|p| p.as_str() == old) else {
            return false;
        };
        *slot = new.to_string();
        for entry in &mut self.entries {
            for p in &mut entry.profiles {
                if p == old {
                    *p = new.to_string();
                }
            }
        }
        self.version += 1;
        true
    }

    // Remove um perfil da lista e limpa essa tag de todas as entradas que a usam.
    // Retorna false se `name` não existir na lista.
    pub(crate) fn delete_profile(&mut self, name: &str) -> bool {
        let before = self.profile_names.len();
        self.profile_names.retain(|p| p != name);
        if self.profile_names.len() == before {
            return false;
        }
        for entry in &mut self.entries {
            entry.profiles.retain(|p| p != name);
        }
        self.version += 1;
        true
    }

    // Marca/desmarca uma entrada como favorita. No-op (sem bump de version)
    // se o id não existir. Mesmo padrão de set_device_permission: mexe só no
    // campo alvo, não passa por upsert (preserva updated_at).
    pub(crate) fn set_favorite(&mut self, id: &str, favorite: bool) -> bool {
        let Some(entry) = self.entries.iter_mut().find(|e| e.id == id) else {
            return false;
        };
        entry.favorite = favorite;
        self.version += 1;
        true
    }

    // Concede/revoga permissão de escrita a um device (find-or-insert).
    pub(crate) fn set_device_permission(&mut self, pub_key: &str, can_write: bool) {
        if let Some(p) = self.device_permissions.iter_mut().find(|p| p.pub_key == pub_key) {
            p.can_write = can_write;
        } else {
            self.device_permissions.push(DeviceVaultPermission {
                pub_key: pub_key.to_string(),
                can_write,
            });
        }
        self.version += 1;
    }
}

// ---------------------------------------------------------------------------
// Helpers internos
// ---------------------------------------------------------------------------

fn new_id() -> String {
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// ---------------------------------------------------------------------------
// I/O em disco
// ---------------------------------------------------------------------------

pub(crate) fn vault_path() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("vault.enc"))
}

// Lê o arquivo cifrado e desserializa o vault.
// Se o arquivo não existe ainda, retorna Vault::default() (primeiro uso).
//
// Migração automática: se o vault foi cifrado com a chave antiga (device-key,
// "vault-key-v1"), ele é decifrado com a chave legada e recifrado com a chave
// nova (wallet-signature, "vault-key-v2") — transparente pro usuário.
pub(crate) fn load() -> Result<Vault, String> {
    let path = vault_path()?;
    if !path.exists() {
        return Ok(Vault::default());
    }
    let blob = std::fs::read(&path).map_err(|e| e.to_string())?;

    // Tenta decifrar com a chave nova (wallet-derived)
    let json = match decrypt(&blob) {
        Ok(json) => json,
        Err(_) => {
            // Fallback: tenta chave legada (device-key) para migração
            if blob.len() < 28 {
                return Err("vault decrypt failed — blob corrupted or wrong key".to_string());
            }
            let legacy_key = derive_vault_key_legacy()?;
            let key = Key::<Aes256Gcm>::from_slice(&legacy_key);
            let cipher = Aes256Gcm::new(key);
            let nonce = Nonce::from_slice(&blob[..12]);
            let legacy_json = cipher
                .decrypt(nonce, &blob[12..])
                .map_err(|_| "vault decrypt failed — blob corrupted or wrong key".to_string())?;

            // Migração: recifra com a chave nova
            let new_key = get_vault_key()
                .map_err(|_| "vault unlocked with legacy key but new key not found — connect wallet to migrate".to_string())?;
            let new_cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&new_key));
            let new_nonce = Aes256Gcm::generate_nonce(&mut OsRng);
            let new_ciphertext = new_cipher
                .encrypt(&new_nonce, legacy_json.as_slice())
                .map_err(|_| "vault re-encrypt during migration failed".to_string())?;
            let mut new_blob = Vec::with_capacity(12 + new_ciphertext.len());
            new_blob.extend_from_slice(&new_nonce);
            new_blob.extend_from_slice(&new_ciphertext);
            std::fs::write(&path, &new_blob).map_err(|e| e.to_string())?;

            legacy_json
        }
    };

    let mut vault: Vault = serde_json::from_slice(&json).map_err(|e| e.to_string())?;
    // Migração: vaults antigos tinham campo "profile" (string única) em vez de "profiles".
    for entry in &mut vault.entries {
        if entry.profiles.is_empty() && !entry.profile.is_empty() {
            entry.profiles = vec![std::mem::take(&mut entry.profile)];
        }
    }
    // Migração: vaults antigos não tinham profile_names — backfill a partir da
    // união das tags já em uso nas entradas (ver PROJECT_STATE.md, Sessão 97).
    if vault.profile_names.is_empty() {
        let mut seen = Vec::new();
        for entry in &vault.entries {
            for p in &entry.profiles {
                if !seen.contains(p) {
                    seen.push(p.clone());
                }
            }
        }
        vault.profile_names = seen;
    }
    // Migração: canWriteVault morava num arquivo local separado
    // (~/.truthid/vault_permissions.json) — backfill único de lá pro campo
    // embutido no vault, pra o Mobile conseguir ler (ver PROJECT_STATE.md,
    // Sessão 97). Best-effort: arquivo ausente ou corrompido só resulta em
    // lista vazia, não é erro fatal.
    if vault.device_permissions.is_empty() {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        let legacy_path = std::path::Path::new(&home)
            .join(".truthid")
            .join("vault_permissions.json");
        if let Ok(raw) = std::fs::read_to_string(&legacy_path) {
            if let Ok(legacy) = serde_json::from_str::<Vec<DeviceVaultPermission>>(&raw) {
                vault.device_permissions = legacy;
            }
        }
    }
    Ok(vault)
}

// Serializa o vault, cifra e escreve em disco.
pub(crate) fn save(vault: &Vault) -> Result<(), String> {
    let json = serde_json::to_vec(vault).map_err(|e| e.to_string())?;
    let blob = encrypt(&json)?;
    let path = vault_path()?;
    std::fs::write(&path, blob).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Cifra / decifra — formato: nonce(12) || ciphertext+tag(n+16)
// ---------------------------------------------------------------------------

pub(crate) fn encrypt(plaintext: &[u8]) -> Result<Vec<u8>, String> {
    let key_bytes = get_vault_key()?;
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
    if blob.len() < 28 {
        return Err("vault blob too short".to_string());
    }
    let key_bytes = get_vault_key()?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);

    let nonce = Nonce::from_slice(&blob[..12]);
    cipher
        .decrypt(nonce, &blob[12..])
        .map_err(|_| "vault decrypt failed — blob corrupted or wrong key".to_string())
}

// ---------------------------------------------------------------------------
// Publicação — rastreia versão publicada vs. versão local
// ---------------------------------------------------------------------------

fn meta_path() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("vault.meta.json"))
}

fn published_snapshot_path() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("vault.published.enc"))
}

// Cópia cifrada (mesma chave do vault.enc) do conteúdo publicado pela última
// vez — usada por `pending_changes` pra diffar entrada por entrada, em vez
// de só comparar hash global. Retorna None se ainda não existe (vault nunca
// publicado desde que este mecanismo foi introduzido, Sessão 139).
fn load_published_snapshot() -> Result<Option<Vault>, String> {
    let path = published_snapshot_path()?;
    if !path.exists() {
        return Ok(None);
    }
    let blob = std::fs::read(&path).map_err(|e| e.to_string())?;
    let json = decrypt(&blob)?;
    let vault: Vault = serde_json::from_slice(&json).map_err(|e| e.to_string())?;
    Ok(Some(vault))
}

fn save_published_snapshot(vault: &Vault) -> Result<(), String> {
    let json = serde_json::to_vec(vault).map_err(|e| e.to_string())?;
    let blob = encrypt(&json)?;
    let path = published_snapshot_path()?;
    std::fs::write(&path, blob).map_err(|e| e.to_string())
}

/// Conta mudanças reais de conteúdo entre o vault atual e o último snapshot
/// publicado — cada entrada adicionada/removida/modificada conta 1, idem pra
/// permissão de device e nome de perfil. Achado da Sessão 139: o diff por
/// hash global (Sessão 138) só zera quando o vault volta 100% idêntico ao
/// publicado — com qualquer outra pendência real no meio (ex: uma entrada
/// nova ainda não publicada), o toggle de favorito voltava a "vazar" porque
/// caía no diff por `version`, que é monotônica e nunca cancela. Diff por
/// entrada resolve isso pra qualquer combinação, sem depender de `version`.
fn diff_count(current: &Vault, published: &Vault) -> u64 {
    use std::collections::{HashMap, HashSet};

    let mut count = 0u64;

    let published_by_id: HashMap<&str, &VaultEntry> =
        published.entries.iter().map(|e| (e.id.as_str(), e)).collect();
    let current_by_id: HashMap<&str, &VaultEntry> =
        current.entries.iter().map(|e| (e.id.as_str(), e)).collect();

    for (id, entry) in &current_by_id {
        match published_by_id.get(id) {
            None => count += 1, // adicionada
            Some(prev) => {
                if serde_json::to_vec(entry).unwrap_or_default()
                    != serde_json::to_vec(prev).unwrap_or_default()
                {
                    count += 1; // modificada
                }
            }
        }
    }
    for id in published_by_id.keys() {
        if !current_by_id.contains_key(id) {
            count += 1; // removida
        }
    }

    let published_perms: HashMap<String, bool> = published
        .device_permissions
        .iter()
        .map(|p| (p.pub_key.to_lowercase(), p.can_write))
        .collect();
    let current_perms: HashMap<String, bool> = current
        .device_permissions
        .iter()
        .map(|p| (p.pub_key.to_lowercase(), p.can_write))
        .collect();
    for (key, can_write) in &current_perms {
        match published_perms.get(key) {
            None => count += 1,
            Some(prev) if prev != can_write => count += 1,
            _ => {}
        }
    }
    for key in published_perms.keys() {
        if !current_perms.contains_key(key) {
            count += 1;
        }
    }

    let published_profiles: HashSet<&String> = published.profile_names.iter().collect();
    let current_profiles: HashSet<&String> = current.profile_names.iter().collect();
    count += current_profiles.difference(&published_profiles).count() as u64;
    count += published_profiles.difference(&current_profiles).count() as u64;

    count
}

/// Assinatura do conteúdo do vault (tudo, exceto `version`) — usada por
/// `pending_changes` pra distinguir "conteúdo diferente do publicado" de "só
/// a versão local subiu". Achado da Sessão 136: favoritar+desfavoritar bumpa
/// version duas vezes mas devolve o conteúdo exato de antes (`set_favorite`
/// preserva `updated_at` de propósito), e a versão sozinha nunca "cancela".
/// Serialização de struct é determinística (ordem de campo fixa do serde),
/// então o hash é estável pro mesmo conteúdo.
fn content_signature(vault: &Vault) -> String {
    #[derive(Serialize)]
    struct Signable<'a> {
        entries: &'a [VaultEntry],
        profile_names: &'a [String],
        device_permissions: &'a [DeviceVaultPermission],
    }
    let signable = Signable {
        entries: &vault.entries,
        profile_names: &vault.profile_names,
        device_permissions: &vault.device_permissions,
    };
    let json = serde_json::to_vec(&signable).unwrap_or_default();
    hex::encode(Sha256::digest(&json))
}

/// Persiste a versão + assinatura de conteúdo do vault que acabou de ser
/// publicado no IPFS, e um snapshot cifrado do conteúdo pra diff futuro
/// (`diff_count`). O meta antigo (hash+version) continua sendo escrito só
/// como fallback pra vaults que ainda não tiverem o snapshot novo (ver
/// `pending_changes`).
pub(crate) fn mark_published(version: u64) -> Result<(), String> {
    let vault = load()?;
    let path = meta_path()?;
    let meta = serde_json::json!({
        "last_published_version": version,
        "last_published_content_hash": content_signature(&vault),
    });
    std::fs::write(&path, serde_json::to_string(&meta).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    save_published_snapshot(&vault)
}

/// Retorna quantas mudanças de conteúdo o vault local tem em relação ao
/// último publicado no IPFS. 0 = nada pendente.
pub(crate) fn pending_changes() -> Result<u64, String> {
    let vault = load()?;
    if let Some(snapshot) = load_published_snapshot()? {
        return Ok(diff_count(&vault, &snapshot));
    }
    // Fallback pra vaults publicados antes da Sessão 139 (sem snapshot local
    // ainda) — mesmo comportamento de antes, até a próxima publicação gravar
    // um snapshot novo e este branch nunca mais rodar pra esse vault.
    let path = meta_path()?;
    if !path.exists() {
        return Ok(vault.version);
    }
    let raw = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let val: serde_json::Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if val["last_published_content_hash"].as_str() == Some(content_signature(&vault).as_str()) {
        return Ok(0);
    }
    let last = val["last_published_version"].as_u64().unwrap_or(0);
    Ok(vault.version.saturating_sub(last))
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // --- testes de cifra (13.3) ---

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
        assert_ne!(blob1, blob2);
        assert_eq!(decrypt(&blob1).unwrap(), b"same");
        assert_eq!(decrypt(&blob2).unwrap(), b"same");
    }

    #[test]
    fn tampered_blob_fails() {
        let mut blob = encrypt(b"sensitive").unwrap();
        blob[15] ^= 0xFF;
        assert!(decrypt(&blob).is_err());
    }

    #[test]
    fn blob_too_short_fails() {
        assert!(decrypt(&[0u8; 10]).is_err());
    }

    // --- testes de CRUD in-memory (13.4) ---

    fn make_entry(id: &str, site: &str) -> VaultEntry {
        VaultEntry {
            id: id.to_string(),
            site: site.to_string(),
            url: String::new(),
            username: "user".to_string(),
            password: "pass".to_string(),
            notes: String::new(),
            profiles: vec![],
            profile: String::new(),
            totp_secret: None,
            passkey: None,
            favorite: false,
            created_at: 0,
            updated_at: 0,
        }
    }

    #[test]
    fn upsert_new_entry_generates_id_and_timestamps() {
        let mut vault = Vault::default();
        let entry = make_entry("", "github.com");
        let saved = vault.upsert(entry);

        assert!(!saved.id.is_empty(), "id deve ser gerado");
        assert!(saved.created_at > 0);
        assert!(saved.updated_at > 0);
        assert_eq!(vault.entries.len(), 1);
        assert_eq!(vault.version, 1);
    }

    #[test]
    fn upsert_existing_id_updates_and_preserves_created_at() {
        let mut vault = Vault::default();
        let first = vault.upsert(make_entry("", "github.com"));
        let created_at = first.created_at;

        // Aguarda 1s para updated_at ser diferente (timestamps em segundos)
        std::thread::sleep(std::time::Duration::from_secs(1));

        let mut updated = first.clone();
        updated.site = "gitlab.com".to_string();
        let saved = vault.upsert(updated);

        assert_eq!(saved.id, first.id);
        assert_eq!(saved.created_at, created_at, "created_at deve ser preservado");
        assert!(saved.updated_at > created_at, "updated_at deve ser renovado");
        assert_eq!(saved.site, "gitlab.com");
        assert_eq!(vault.entries.len(), 1);
        assert_eq!(vault.version, 2);
    }

    #[test]
    fn upsert_unknown_id_creates_new_entry_with_that_id() {
        let mut vault = Vault::default();
        let entry = make_entry("custom-id-abc", "example.com");
        let saved = vault.upsert(entry);

        assert_eq!(saved.id, "custom-id-abc");
        assert_eq!(vault.entries.len(), 1);
    }

    #[test]
    fn delete_existing_entry_returns_true() {
        let mut vault = Vault::default();
        let entry = vault.upsert(make_entry("", "github.com"));
        let removed = vault.delete(&entry.id);

        assert!(removed);
        assert!(vault.entries.is_empty());
        assert_eq!(vault.version, 2); // 1 do upsert + 1 do delete
    }

    #[test]
    fn delete_nonexistent_id_returns_false() {
        let mut vault = Vault::default();
        let removed = vault.delete("id-inexistente");
        assert!(!removed);
        assert_eq!(vault.version, 0); // version não muda
    }

    #[test]
    fn multiple_entries_preserved() {
        let mut vault = Vault::default();
        let a = vault.upsert(make_entry("", "github.com"));
        let b = vault.upsert(make_entry("", "google.com"));
        vault.upsert(make_entry("", "notion.so"));

        assert_eq!(vault.entries.len(), 3);

        vault.delete(&b.id);
        assert_eq!(vault.entries.len(), 2);
        assert!(vault.entries.iter().any(|e| e.id == a.id));
        assert!(!vault.entries.iter().any(|e| e.id == b.id));
    }

    // --- testes de perfis nomeados (Sessão 97) ---

    #[test]
    fn add_profile_appends_new_name() {
        let mut vault = Vault::default();
        vault.add_profile("Trabalho");
        assert_eq!(vault.profile_names, vec!["Trabalho"]);
        assert_eq!(vault.version, 1);
    }

    #[test]
    fn add_profile_is_noop_for_duplicate() {
        let mut vault = Vault::default();
        vault.add_profile("Trabalho");
        vault.add_profile("Trabalho");
        assert_eq!(vault.profile_names, vec!["Trabalho"]);
        assert_eq!(vault.version, 1, "segunda chamada não deve incrementar version");
    }

    #[test]
    fn rename_profile_updates_list_and_cascades_into_entries() {
        let mut vault = Vault::default();
        vault.add_profile("Trabalho");
        let mut entry = make_entry("", "github.com");
        entry.profiles = vec!["Trabalho".to_string(), "Pessoal".to_string()];
        vault.upsert(entry);

        let ok = vault.rename_profile("Trabalho", "Banco");

        assert!(ok);
        assert_eq!(vault.profile_names, vec!["Banco"]);
        assert_eq!(vault.entries[0].profiles, vec!["Banco".to_string(), "Pessoal".to_string()]);
    }

    #[test]
    fn rename_profile_unknown_returns_false() {
        let mut vault = Vault::default();
        assert!(!vault.rename_profile("Inexistente", "Novo"));
    }

    #[test]
    fn delete_profile_removes_from_list_and_entries() {
        let mut vault = Vault::default();
        vault.add_profile("Trabalho");
        let mut entry = make_entry("", "github.com");
        entry.profiles = vec!["Trabalho".to_string(), "Pessoal".to_string()];
        vault.upsert(entry);

        let ok = vault.delete_profile("Trabalho");

        assert!(ok);
        assert!(vault.profile_names.is_empty());
        assert_eq!(vault.entries[0].profiles, vec!["Pessoal".to_string()]);
    }

    #[test]
    fn delete_profile_unknown_returns_false() {
        let mut vault = Vault::default();
        assert!(!vault.delete_profile("Inexistente"));
    }

    #[test]
    fn load_backfills_profile_names_from_existing_entry_tags() {
        // Simula um vault antigo serializado sem o campo "profile_names".
        let mut vault = Vault::default();
        let mut a = make_entry("", "github.com");
        a.profiles = vec!["Trabalho".to_string()];
        vault.upsert(a);
        let mut b = make_entry("", "google.com");
        b.profiles = vec!["Trabalho".to_string(), "Casa".to_string()];
        vault.upsert(b);
        vault.profile_names = vec![]; // como um vault serializado antes desta mudança

        let json = serde_json::to_vec(&vault).unwrap();
        let mut reparsed: Vault = serde_json::from_slice(&json).unwrap();
        // reaplica a mesma lógica de backfill que load() roda após desserializar
        if reparsed.profile_names.is_empty() {
            let mut seen = Vec::new();
            for entry in &reparsed.entries {
                for p in &entry.profiles {
                    if !seen.contains(p) {
                        seen.push(p.clone());
                    }
                }
            }
            reparsed.profile_names = seen;
        }

        assert_eq!(reparsed.profile_names, vec!["Trabalho".to_string(), "Casa".to_string()]);
    }

    // --- testes de favoritos ---

    #[test]
    fn set_favorite_marks_existing_entry() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));

        let found = vault.set_favorite("id1", true);

        assert!(found);
        assert!(vault.entries[0].favorite);
        assert_eq!(vault.version, 1);
    }

    #[test]
    fn set_favorite_unmarks_existing_entry() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        vault.set_favorite("id1", true);
        vault.set_favorite("id1", false);

        assert!(!vault.entries[0].favorite);
        assert_eq!(vault.version, 2);
    }

    #[test]
    fn set_favorite_preserves_other_fields_including_updated_at() {
        let mut vault = Vault::default();
        let mut entry = make_entry("id1", "github.com");
        entry.updated_at = 12345;
        vault.entries.push(entry);

        vault.set_favorite("id1", true);

        assert_eq!(vault.entries[0].updated_at, 12345, "updated_at não deve mudar só por favoritar");
        assert_eq!(vault.entries[0].site, "github.com");
    }

    #[test]
    fn set_favorite_only_affects_the_targeted_entry() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        vault.entries.push(make_entry("id2", "gitlab.com"));

        vault.set_favorite("id1", true);

        assert!(vault.entries[0].favorite);
        assert!(!vault.entries[1].favorite);
    }

    #[test]
    fn set_favorite_unknown_id_is_noop() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));

        let found = vault.set_favorite("does-not-exist", true);

        assert!(!found);
        assert_eq!(vault.version, 0, "id inexistente não deve bumpar version");
    }

    // --- testes de content_signature / pending_changes (Sessão 138, item 7) ---

    #[test]
    fn content_signature_ignores_version() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        let sig_before = content_signature(&vault);
        vault.version += 5; // simula bumps de version sem mudar conteúdo
        assert_eq!(content_signature(&vault), sig_before);
    }

    #[test]
    fn content_signature_changes_with_entry_content() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        let sig_before = content_signature(&vault);
        vault.set_favorite("id1", true);
        assert_ne!(content_signature(&vault), sig_before);
    }

    #[test]
    fn content_signature_matches_after_favorite_toggle_round_trip() {
        // Achado da Sessão 136: favoritar+desfavoritar bumpa version duas
        // vezes, mas o conteúdo final é idêntico ao original — a assinatura
        // precisa "cancelar" mesmo a version não cancelando.
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        let sig_before = content_signature(&vault);

        vault.set_favorite("id1", true);
        vault.set_favorite("id1", false);

        assert_eq!(vault.version, 2);
        assert_eq!(content_signature(&vault), sig_before);
    }

    // --- testes de diff_count (Sessão 139, achado: toggle não cancelava com
    // outra pendência real no meio) ---

    #[test]
    fn diff_count_zero_for_identical_vaults() {
        let mut vault = Vault::default();
        vault.entries.push(make_entry("id1", "github.com"));
        let published = Vault {
            version: vault.version,
            entries: vault.entries.clone(),
            profile_names: vault.profile_names.clone(),
            device_permissions: vault.device_permissions.clone(),
        };
        assert_eq!(diff_count(&vault, &published), 0);
    }

    #[test]
    fn diff_count_counts_new_entry() {
        let published = Vault::default();
        let mut current = Vault::default();
        current.entries.push(make_entry("id1", "github.com"));
        assert_eq!(diff_count(&current, &published), 1);
    }

    #[test]
    fn diff_count_toggle_cancels_even_with_other_pending_entry() {
        // Reprodução exata do bug real: uma entrada nova (pendência real,
        // nunca publicada) + favoritar/desfavoritar outra entrada já
        // publicada. O diff por entrada não deve contar o toggle, só a
        // entrada nova de fato pendente.
        let mut published = Vault::default();
        published.entries.push(make_entry("id1", "github.com"));

        let mut current = Vault {
            version: published.version,
            entries: published.entries.clone(),
            profile_names: published.profile_names.clone(),
            device_permissions: published.device_permissions.clone(),
        };
        current.entries.push(make_entry("id2", "b.com")); // pendência real
        assert_eq!(diff_count(&current, &published), 1);

        current.set_favorite("id1", true);
        assert_eq!(diff_count(&current, &published), 2);

        current.set_favorite("id1", false);
        assert_eq!(
            diff_count(&current, &published),
            1,
            "toggle deveria cancelar, sobrando só a entrada nova"
        );
    }

    #[test]
    fn diff_count_counts_removed_entry_and_permission_change() {
        let mut published = Vault::default();
        published.entries.push(make_entry("id1", "github.com"));
        published.device_permissions.push(DeviceVaultPermission {
            pub_key: "0xABC".to_string(),
            can_write: false,
        });

        let mut current = Vault::default();
        current.device_permissions.push(DeviceVaultPermission {
            pub_key: "0xabc".to_string(), // mesma chave, case diferente
            can_write: true,              // mudou
        });

        // entrada removida (1) + permissão mudou (1)
        assert_eq!(diff_count(&current, &published), 2);
    }

    // --- testes de permissão de escrita por device (Sessão 97) ---

    #[test]
    fn set_device_permission_inserts_new() {
        let mut vault = Vault::default();
        vault.set_device_permission("0xabc", true);

        assert_eq!(vault.device_permissions.len(), 1);
        assert_eq!(vault.device_permissions[0].pub_key, "0xabc");
        assert!(vault.device_permissions[0].can_write);
        assert_eq!(vault.version, 1);
    }

    #[test]
    fn set_device_permission_updates_existing() {
        let mut vault = Vault::default();
        vault.set_device_permission("0xabc", true);
        vault.set_device_permission("0xabc", false);

        assert_eq!(vault.device_permissions.len(), 1);
        assert!(!vault.device_permissions[0].can_write);
        assert_eq!(vault.version, 2);
    }

    #[test]
    fn set_device_permission_preserves_other_devices() {
        let mut vault = Vault::default();
        vault.set_device_permission("0xaaa", true);
        vault.set_device_permission("0xbbb", false);

        assert_eq!(vault.device_permissions.len(), 2);
        assert!(vault.device_permissions.iter().any(|p| p.pub_key == "0xaaa" && p.can_write));
        assert!(vault.device_permissions.iter().any(|p| p.pub_key == "0xbbb" && !p.can_write));
    }

    #[test]
    fn load_backfills_device_permissions_from_legacy_file() {
        // Simula o arquivo legado ~/.truthid/vault_permissions.json existindo
        // com permissões de uma versão anterior à Sessão 97.
        let legacy = vec![
            DeviceVaultPermission { pub_key: "0xaaa".to_string(), can_write: true },
        ];
        let json = serde_json::to_string(&legacy).unwrap();
        let mut vault = Vault::default();
        assert!(vault.device_permissions.is_empty());

        // Reaplica a mesma lógica de backfill que load() roda (sem tocar no
        // HOME real do processo de teste).
        if vault.device_permissions.is_empty() {
            if let Ok(parsed) = serde_json::from_str::<Vec<DeviceVaultPermission>>(&json) {
                vault.device_permissions = parsed;
            }
        }

        assert_eq!(vault.device_permissions.len(), 1);
        assert_eq!(vault.device_permissions[0].pub_key, "0xaaa");
    }
}

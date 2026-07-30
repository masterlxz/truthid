use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Mutex;

use crate::{derive_vault_key_legacy, get_vault_key};

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
    /// Discriminante de tipo (Fase 15). Ausente em blobs antigos → default
    /// `Credential`, que é o único tipo que existia antes desta mudança —
    /// mesmo mecanismo de back-compat que `favorite`/`passkey` já usam.
    #[serde(default)]
    pub r#type: EntryType,
    /// Presente só se `type == Document`. Ver `VaultEntry::validate`.
    #[serde(default)]
    pub document: Option<DocumentData>,
    /// Presente só se `type == Address`. Ver `VaultEntry::validate`.
    #[serde(default)]
    pub address: Option<AddressData>,
    /// Presente só se `type == CreditCard`. Cifra individual extra de
    /// `card_number`/`cvv` fica pra 15.8 (revisão de segurança) — por ora
    /// os dois viajam em texto plano dentro do blob, que já é cifrado como
    /// um todo (AES-256-GCM).
    #[serde(default)]
    pub credit_card: Option<CreditCardData>,
    pub created_at: u64,
    pub updated_at: u64,
}

impl VaultEntry {
    /// Garante que só o grupo de dados correspondente ao `type` está
    /// presente — evita representar um estado inconsistente (ex: uma
    /// entrada "address" carregando também dados de cartão). Chamado no
    /// início de `Vault::upsert`.
    pub(crate) fn validate(&self) -> Result<(), String> {
        let (document, address, credit_card) = (
            self.document.is_some(),
            self.address.is_some(),
            self.credit_card.is_some(),
        );
        let ok = match self.r#type {
            EntryType::Credential => !document && !address && !credit_card,
            EntryType::Document => document && !address && !credit_card,
            EntryType::Address => !document && address && !credit_card,
            EntryType::CreditCard => !document && !address && credit_card,
        };
        if ok {
            Ok(())
        } else {
            Err(format!(
                "vault entry type {:?} doesn't match its data groups (document={document}, address={address}, credit_card={credit_card})",
                self.r#type
            ))
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum EntryType {
    #[default]
    Credential,
    Document,
    Address,
    CreditCard,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct DocumentData {
    pub name: String,
    pub file_name: String,
    /// Campo legado (pré-Fase 15.7) — conteúdo em base64 embutido direto no
    /// blob do vault. Inflava o sync de TODO o vault por causa de qualquer
    /// documento grande, mesmo pra edições não relacionadas (ver
    /// project/PHASE.md, 15.7). Só existe pra migração automática em
    /// `load()`; nunca mais escrito (privado + `skip_serializing`) — o
    /// conteúdo agora vive cifrado à parte (`vault_documents/<id>.enc`),
    /// referenciado por `cid`/`content_hash` abaixo.
    #[serde(default, skip_serializing)]
    file_data: String,
    pub file_size_bytes: u64,
    pub mime_type: String,
    /// CID do blob cifrado do documento no IPFS — `None` até o próximo
    /// publish pinar o conteúdo (ver `vault_publish` em `lib.rs`).
    #[serde(default)]
    pub cid: Option<String>,
    /// keccak256 (hex, prefixo "0x") do blob cifrado do documento — mesmo
    /// padrão de verificação que o vault principal já usa antes de decifrar
    /// um blob baixado do IPFS. Também usado localmente pra decidir se o
    /// documento mudou desde o último pin (`document_needs_pin`).
    #[serde(default)]
    pub content_hash: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct AddressData {
    pub label: String,
    pub full_name: String,
    pub street: String,
    pub number: String,
    #[serde(default)]
    pub complement: Option<String>,
    pub neighborhood: String,
    pub city: String,
    pub state: String,
    pub zip_code: String,
    pub country: String,
    #[serde(default)]
    pub phone: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct CreditCardData {
    pub label: String,
    pub card_holder_name: String,
    pub card_number: String,
    pub expiry_month: String,
    pub expiry_year: String,
    pub cvv: String,
    #[serde(default)]
    pub bank: Option<String>,
    pub card_network: CardNetwork,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum CardNetwork {
    Visa,
    Mastercard,
    Amex,
    Elo,
    Hipercard,
    #[serde(other)]
    Other,
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
/// terceiros desconfiados — ver VaultRegistry.sol e project/INDEX.md, 13.7).
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
    /// não é mais uma lista fixa — ver project/INDEX.md, Sessão 97.
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
    pub(crate) fn upsert(&mut self, mut entry: VaultEntry) -> Result<VaultEntry, String> {
        entry.validate()?;

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

        Ok(entry)
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
        if let Some(p) = self
            .device_permissions
            .iter_mut()
            .find(|p| p.pub_key == pub_key)
        {
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

/// Mutex serializando todas as operações de load→mutate→save no vault. Sem
/// esta trava, duas chamadas concorrentes (ex: `vault_upsert_entry` + `vault_set_favorite`)
/// perdem dados: ambas leem o mesmo `vault.enc`, modificam suas cópias em
/// memória, e a última `save()` sobrescreve a mudança da outra (bug #3).
static VAULT_MUTEX: Mutex<()> = Mutex::new(());

/// Adquire a trava do vault. Comandos de mutação chamam isso no início para
/// garantir exclusão mútua entre load→mutate→save. Comandos de leitura podem
/// pular (race de leitura não perde dados).
pub(crate) fn lock_vault() -> std::sync::MutexGuard<'static, ()> {
    VAULT_MUTEX
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

pub(crate) fn vault_path() -> Result<PathBuf, String> {
    crate::config::truthid_file_path("vault.enc")
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
    let blob = crate::config::read_file(&path)?;

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
            crate::config::write_file(&path, &new_blob)?;

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
    // união das tags já em uso nas entradas (ver project/INDEX.md, Sessão 97).
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
    // embutido no vault, pra o Mobile conseguir ler (ver project/INDEX.md,
    // Sessão 97). Best-effort: arquivo ausente ou corrompido só resulta em
    // lista vazia, não é erro fatal.
    if vault.device_permissions.is_empty() {
        let legacy_path =
            crate::config::truthid_file_path("vault_permissions.json").unwrap_or_default();
        if legacy_path.exists() {
            if let Ok(raw) = crate::config::read_text(&legacy_path) {
                if let Ok(legacy) = serde_json::from_str::<Vec<DeviceVaultPermission>>(&raw) {
                    vault.device_permissions = legacy;
                }
            }
        }
    }
    // Migração (Fase 15.7): documentos antigos guardavam o conteúdo em
    // base64 embutido direto no blob do vault (`file_data`). Uma entrada com
    // `file_data` ainda preenchido e `cid` ausente não passou pela migração
    // ainda — decifra o base64 legado, escreve no cache local de documentos,
    // e deixa `cid`/`content_hash` em None pro próximo `vault_publish` pinar
    // como blob separado (o pin em si não acontece aqui, `load()` é síncrono
    // e só lê disco).
    {
        use base64::{engine::general_purpose::STANDARD, Engine as _};
        for entry in &mut vault.entries {
            if let Some(doc) = &mut entry.document {
                if !doc.file_data.is_empty() && doc.cid.is_none() {
                    if let Ok(raw) = STANDARD.decode(&doc.file_data) {
                        let _ = write_document_blob(&entry.id, &raw);
                    }
                    doc.file_data = String::new();
                }
            }
        }
    }
    Ok(vault)
}

// ---------------------------------------------------------------------------
// Cache local de documentos (Fase 15.7)
// ---------------------------------------------------------------------------

// Diretório onde o conteúdo cifrado de cada documento vive localmente, à
// parte do blob principal do vault — só um CID/hash aponta pra cá de dentro
// do vault.enc (ver `DocumentData::cid`/`content_hash`). Motivo: um
// documento grande não deve inflar o blob que é sincronizado a cada edição
// não relacionada (ver project/PHASE.md, 15.7).
fn document_path(entry_id: &str) -> Result<PathBuf, String> {
    crate::config::truthid_file_path(&format!("vault_documents/{entry_id}.enc"))
}

/// Lê o blob cifrado do documento de uma entrada, se existir localmente.
/// `None` se essa entrada nunca teve conteúdo salvo neste device (ex:
/// documento adicionado em outro device, ainda não buscado por CID).
pub(crate) fn read_document_blob(entry_id: &str) -> Result<Option<Vec<u8>>, String> {
    let path = document_path(entry_id)?;
    if !path.exists() {
        return Ok(None);
    }
    Ok(Some(crate::config::read_file(&path)?))
}

/// Cifra e grava o conteúdo em claro de um documento no cache local.
/// Retorna o blob cifrado (evita reler do disco pra computar o hash na hora
/// de pinar).
pub(crate) fn write_document_blob(entry_id: &str, plaintext: &[u8]) -> Result<Vec<u8>, String> {
    let blob = encrypt(plaintext)?;
    let path = document_path(entry_id)?;
    crate::config::write_file(&path, &blob)?;
    Ok(blob)
}

/// Grava um blob **já cifrado** no cache local, sem recifrar — usado ao
/// buscar o conteúdo de um documento por CID (já vem cifrado do IPFS, ver
/// `vault_document_read` em `lib.rs`).
pub(crate) fn cache_document_blob_raw(entry_id: &str, encrypted: &[u8]) -> Result<(), String> {
    let path = document_path(entry_id)?;
    crate::config::write_file(&path, encrypted)
}

/// Decide se o conteúdo local de um documento precisa ser (re)pinado — `true`
/// se nunca foi pinado (`stored_hash` é `None`) ou se o hash do blob local
/// não bate com o último hash pinado. Evita rechamar `pin_vault` (rede) numa
/// publicação onde só outra entrada do vault mudou.
pub(crate) fn document_needs_pin(local_blob: &[u8], stored_hash: Option<&str>) -> bool {
    match stored_hash {
        None => true,
        Some(hash) => crate::ipfs::keccak256_hex(local_blob) != hash,
    }
}

// Serializa o vault, cifra e escreve em disco.
pub(crate) fn save(vault: &Vault) -> Result<(), String> {
    let json = serde_json::to_vec(vault).map_err(|e| e.to_string())?;
    let blob = encrypt(&json)?;
    let path = vault_path()?;
    crate::config::write_file(&path, &blob)
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
    crate::config::truthid_file_path("vault.meta.json")
}

fn published_snapshot_path() -> Result<PathBuf, String> {
    crate::config::truthid_file_path("vault.published.enc")
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
    let blob = crate::config::read_file(&path)?;
    let json = decrypt(&blob)?;
    let vault: Vault = serde_json::from_slice(&json).map_err(|e| e.to_string())?;
    Ok(Some(vault))
}

fn save_published_snapshot(vault: &Vault) -> Result<(), String> {
    let json = serde_json::to_vec(vault).map_err(|e| e.to_string())?;
    let blob = encrypt(&json)?;
    let path = published_snapshot_path()?;
    crate::config::write_file(&path, &blob)
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

    let published_by_id: HashMap<&str, &VaultEntry> = published
        .entries
        .iter()
        .map(|e| (e.id.as_str(), e))
        .collect();
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
///
/// Recebe o vault que foi de fato publicado (em vez de reler do disco) —
/// achado da Sessão 153 (M3, mesmo TOCTOU achado no Mobile pelo
/// `/code-review high`): entre o `vault_publish` ler o blob e chamar isto
/// aqui existe um `.await` de rede (pin no IPFS); reler o disco depois
/// capturava qualquer edição feita nesse meio-tempo como se já tivesse sido
/// publicada.
pub(crate) fn mark_published(version: u64, published_vault: &Vault) -> Result<(), String> {
    let path = meta_path()?;
    let meta = serde_json::json!({
        "last_published_version": version,
        "last_published_content_hash": content_signature(published_vault),
    });
    crate::config::write_text(
        &path,
        &serde_json::to_string(&meta).map_err(|e| e.to_string())?,
    )?;
    save_published_snapshot(published_vault)
}

/// Retorna quantas mudanças de conteúdo o vault local tem em relação ao
/// último publicado no IPFS. 0 = nada pendente.
pub(crate) fn pending_changes() -> Result<u64, String> {
    pending_changes_from(&load()?)
}

/// Mesmo que `pending_changes()`, mas recebe o vault já carregado —
/// evita um reload+decrypt redundante quando o caller já tem o vault
/// em memória (ex: `vault_load_all`).
pub(crate) fn pending_changes_from(vault: &Vault) -> Result<u64, String> {
    if let Some(snapshot) = load_published_snapshot()? {
        return Ok(diff_count(vault, &snapshot));
    }
    // Fallback pra vaults publicados antes da Sessão 139 (sem snapshot local
    // ainda) — mesmo comportamento de antes, até a próxima publicação gravar
    // um snapshot novo e este branch nunca mais rodar pra esse vault.
    let path = meta_path()?;
    if !path.exists() {
        return Ok(vault.version);
    }
    let raw = crate::config::read_text(&path)?;
    let val: serde_json::Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if val["last_published_content_hash"].as_str() == Some(content_signature(vault).as_str()) {
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
            r#type: EntryType::Credential,
            document: None,
            address: None,
            credit_card: None,
            created_at: 0,
            updated_at: 0,
        }
    }

    #[test]
    fn upsert_new_entry_generates_id_and_timestamps() {
        let mut vault = Vault::default();
        let entry = make_entry("", "github.com");
        let saved = vault.upsert(entry).unwrap();

        assert!(!saved.id.is_empty(), "id deve ser gerado");
        assert!(saved.created_at > 0);
        assert!(saved.updated_at > 0);
        assert_eq!(vault.entries.len(), 1);
        assert_eq!(vault.version, 1);
    }

    #[test]
    fn upsert_existing_id_updates_and_preserves_created_at() {
        let mut vault = Vault::default();
        let first = vault.upsert(make_entry("", "github.com")).unwrap();
        let created_at = first.created_at;

        // Aguarda 1s para updated_at ser diferente (timestamps em segundos)
        std::thread::sleep(std::time::Duration::from_secs(1));

        let mut updated = first.clone();
        updated.site = "gitlab.com".to_string();
        let saved = vault.upsert(updated).unwrap();

        assert_eq!(saved.id, first.id);
        assert_eq!(
            saved.created_at, created_at,
            "created_at deve ser preservado"
        );
        assert!(
            saved.updated_at > created_at,
            "updated_at deve ser renovado"
        );
        assert_eq!(saved.site, "gitlab.com");
        assert_eq!(vault.entries.len(), 1);
        assert_eq!(vault.version, 2);
    }

    #[test]
    fn upsert_unknown_id_creates_new_entry_with_that_id() {
        let mut vault = Vault::default();
        let entry = make_entry("custom-id-abc", "example.com");
        let saved = vault.upsert(entry).unwrap();

        assert_eq!(saved.id, "custom-id-abc");
        assert_eq!(vault.entries.len(), 1);
    }

    #[test]
    fn delete_existing_entry_returns_true() {
        let mut vault = Vault::default();
        let entry = vault.upsert(make_entry("", "github.com")).unwrap();
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
        let a = vault.upsert(make_entry("", "github.com")).unwrap();
        let b = vault.upsert(make_entry("", "google.com")).unwrap();
        vault.upsert(make_entry("", "notion.so")).unwrap();

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
        assert_eq!(
            vault.version, 1,
            "segunda chamada não deve incrementar version"
        );
    }

    #[test]
    fn rename_profile_updates_list_and_cascades_into_entries() {
        let mut vault = Vault::default();
        vault.add_profile("Trabalho");
        let mut entry = make_entry("", "github.com");
        entry.profiles = vec!["Trabalho".to_string(), "Pessoal".to_string()];
        vault.upsert(entry).unwrap();

        let ok = vault.rename_profile("Trabalho", "Banco");

        assert!(ok);
        assert_eq!(vault.profile_names, vec!["Banco"]);
        assert_eq!(
            vault.entries[0].profiles,
            vec!["Banco".to_string(), "Pessoal".to_string()]
        );
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
        vault.upsert(entry).unwrap();

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
        vault.upsert(a).unwrap();
        let mut b = make_entry("", "google.com");
        b.profiles = vec!["Trabalho".to_string(), "Casa".to_string()];
        vault.upsert(b).unwrap();
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

        assert_eq!(
            reparsed.profile_names,
            vec!["Trabalho".to_string(), "Casa".to_string()]
        );
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

        assert_eq!(
            vault.entries[0].updated_at, 12345,
            "updated_at não deve mudar só por favoritar"
        );
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
        assert!(vault
            .device_permissions
            .iter()
            .any(|p| p.pub_key == "0xaaa" && p.can_write));
        assert!(vault
            .device_permissions
            .iter()
            .any(|p| p.pub_key == "0xbbb" && !p.can_write));
    }

    #[test]
    fn load_backfills_device_permissions_from_legacy_file() {
        // Simula o arquivo legado ~/.truthid/vault_permissions.json existindo
        // com permissões de uma versão anterior à Sessão 97.
        let legacy = vec![DeviceVaultPermission {
            pub_key: "0xaaa".to_string(),
            can_write: true,
        }];
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

    // --- testes de schema Fase 15.1 (documentos/endereços/cartões) ---

    fn make_document_entry(id: &str) -> VaultEntry {
        let mut entry = make_entry(id, "");
        entry.r#type = EntryType::Document;
        entry.document = Some(DocumentData {
            name: "RG".to_string(),
            file_name: "rg.pdf".to_string(),
            file_data: String::new(),
            file_size_bytes: 12345,
            mime_type: "application/pdf".to_string(),
            cid: None,
            content_hash: None,
        });
        entry
    }

    fn make_address_entry(id: &str) -> VaultEntry {
        let mut entry = make_entry(id, "");
        entry.r#type = EntryType::Address;
        entry.address = Some(AddressData {
            label: "Casa".to_string(),
            full_name: "Fabio Junior".to_string(),
            street: "Rua X".to_string(),
            number: "123".to_string(),
            complement: None,
            neighborhood: "Centro".to_string(),
            city: "São Paulo".to_string(),
            state: "SP".to_string(),
            zip_code: "01000-000".to_string(),
            country: "BR".to_string(),
            phone: None,
        });
        entry
    }

    fn make_credit_card_entry(id: &str) -> VaultEntry {
        let mut entry = make_entry(id, "");
        entry.r#type = EntryType::CreditCard;
        entry.credit_card = Some(CreditCardData {
            label: "Nubank".to_string(),
            card_holder_name: "Fabio Junior".to_string(),
            card_number: "4111111111111111".to_string(),
            expiry_month: "12".to_string(),
            expiry_year: "2030".to_string(),
            cvv: "123".to_string(),
            bank: None,
            card_network: CardNetwork::Visa,
        });
        entry
    }

    #[test]
    fn old_blob_without_type_deserializes_as_credential() {
        // Formato antigo (pré-Fase 15): nenhum dos 4 campos novos existe no JSON.
        let old_json = br#"{
            "id": "id1",
            "site": "github.com",
            "url": "",
            "username": "user",
            "password": "pass",
            "notes": "",
            "profiles": [],
            "created_at": 0,
            "updated_at": 0
        }"#;
        let entry: VaultEntry = serde_json::from_slice(old_json).unwrap();

        assert_eq!(entry.r#type, EntryType::Credential);
        assert!(entry.document.is_none());
        assert!(entry.address.is_none());
        assert!(entry.credit_card.is_none());
        assert!(entry.validate().is_ok());
    }

    #[test]
    fn document_entry_round_trips_through_json() {
        let entry = make_document_entry("id1");
        let json = serde_json::to_vec(&entry).unwrap();
        let reparsed: VaultEntry = serde_json::from_slice(&json).unwrap();

        assert_eq!(reparsed.r#type, EntryType::Document);
        assert_eq!(reparsed.document.unwrap().name, "RG");
        assert!(reparsed.address.is_none());
        assert!(reparsed.credit_card.is_none());
    }

    #[test]
    fn address_entry_round_trips_through_json() {
        let entry = make_address_entry("id1");
        let json = serde_json::to_vec(&entry).unwrap();
        let reparsed: VaultEntry = serde_json::from_slice(&json).unwrap();

        assert_eq!(reparsed.r#type, EntryType::Address);
        assert_eq!(reparsed.address.unwrap().city, "São Paulo");
        assert!(reparsed.document.is_none());
        assert!(reparsed.credit_card.is_none());
    }

    #[test]
    fn credit_card_entry_round_trips_through_json() {
        let entry = make_credit_card_entry("id1");
        let json = serde_json::to_vec(&entry).unwrap();
        let reparsed: VaultEntry = serde_json::from_slice(&json).unwrap();

        assert_eq!(reparsed.r#type, EntryType::CreditCard);
        let card = reparsed.credit_card.unwrap();
        assert_eq!(card.card_number, "4111111111111111");
        assert_eq!(card.card_network, CardNetwork::Visa);
        assert!(reparsed.document.is_none());
        assert!(reparsed.address.is_none());
    }

    #[test]
    fn unknown_card_network_falls_back_to_other() {
        // Forward-compat: um valor de card_network desconhecido (ex: uma
        // bandeira nova adicionada por uma versão futura) não deve quebrar a
        // desserialização numa versão antiga do app.
        let json = br#""some_future_network""#;
        let network: CardNetwork = serde_json::from_slice(json).unwrap();
        assert_eq!(network, CardNetwork::Other);
    }

    #[test]
    fn validate_rejects_mismatched_type_and_data_group() {
        let mut entry = make_address_entry("id1");
        // Corrompe o invariante: type=Address mas carrega dados de cartão também.
        entry.credit_card = Some(CreditCardData {
            label: "x".to_string(),
            card_holder_name: "x".to_string(),
            card_number: "x".to_string(),
            expiry_month: "x".to_string(),
            expiry_year: "x".to_string(),
            cvv: "x".to_string(),
            bank: None,
            card_network: CardNetwork::Other,
        });

        assert!(entry.validate().is_err());
    }

    #[test]
    fn validate_rejects_type_without_its_data_group() {
        let mut entry = make_document_entry("id1");
        entry.document = None; // type=Document mas sem os dados do documento

        assert!(entry.validate().is_err());
    }

    #[test]
    fn upsert_rejects_invalid_entry_and_does_not_bump_version() {
        let mut vault = Vault::default();
        let mut invalid = make_address_entry("");
        invalid.address = None; // inválido: type=Address sem dados de endereço

        let result = vault.upsert(invalid);

        assert!(result.is_err());
        assert_eq!(vault.version, 0, "upsert inválido não deve bumpar version");
        assert!(vault.entries.is_empty());
    }

    #[test]
    fn upsert_accepts_each_new_entry_type() {
        let mut vault = Vault::default();
        vault.upsert(make_document_entry("")).unwrap();
        vault.upsert(make_address_entry("")).unwrap();
        vault.upsert(make_credit_card_entry("")).unwrap();

        assert_eq!(vault.entries.len(), 3);
        assert_eq!(vault.entries[0].r#type, EntryType::Document);
        assert_eq!(vault.entries[1].r#type, EntryType::Address);
        assert_eq!(vault.entries[2].r#type, EntryType::CreditCard);
    }

    // --- testes de schema/cache Fase 15.7 (documentos separados do blob) ---
    //
    // Nota: `read_document_blob`/`write_document_blob` tocam disco real via
    // `crate::config::truthid_file_path` — mesma limitação já documentada
    // pro resto do módulo (sem infra de path override em testes, ver Sessão
    // 154). Os testes abaixo cobrem só a lógica pura (schema/migração via
    // JSON, `document_needs_pin`), sem escrever no disco real.

    #[test]
    fn document_data_new_format_has_no_content_embedded() {
        let entry = make_document_entry("id1");
        let json = serde_json::to_vec(&entry).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&json).unwrap();
        assert!(
            value["document"].get("file_data").is_none(),
            "file_data não deve aparecer no JSON serializado (skip_serializing)"
        );
    }

    #[test]
    fn document_entry_round_trips_cid_and_content_hash() {
        let mut entry = make_document_entry("id1");
        entry.document.as_mut().unwrap().cid = Some("bafy123".to_string());
        entry.document.as_mut().unwrap().content_hash = Some("0xabc".to_string());

        let json = serde_json::to_vec(&entry).unwrap();
        let reparsed: VaultEntry = serde_json::from_slice(&json).unwrap();

        let doc = reparsed.document.unwrap();
        assert_eq!(doc.cid, Some("bafy123".to_string()));
        assert_eq!(doc.content_hash, Some("0xabc".to_string()));
    }

    #[test]
    fn old_format_document_json_migrates_schema_on_deserialize() {
        // Formato antigo (pré-Fase 15.7): file_data embutido, sem cid/content_hash.
        let old_json = br#"{
            "id": "id1",
            "site": "",
            "url": "",
            "username": "user",
            "password": "pass",
            "notes": "",
            "profiles": [],
            "type": "document",
            "document": {
                "name": "RG",
                "file_name": "rg.pdf",
                "file_data": "aGVsbG8=",
                "file_size_bytes": 5,
                "mime_type": "application/pdf"
            },
            "created_at": 0,
            "updated_at": 0
        }"#;
        let entry: VaultEntry = serde_json::from_slice(old_json).unwrap();
        let doc = entry.document.unwrap();

        // cid/content_hash ausentes no JSON antigo -> None, sinaliza "ainda
        // não migrado/pinado" pro próximo load()/vault_publish.
        assert_eq!(doc.cid, None);
        assert_eq!(doc.content_hash, None);
        // file_data é lido (via serde default) só pra load() migrar — não é
        // exposto publicamente, mas o campo existe internamente até load()
        // rodar a migração (testada separadamente via write_document_blob
        // não tocar disco aqui).
    }

    #[test]
    fn document_needs_pin_true_when_never_pinned() {
        assert!(document_needs_pin(b"conteudo", None));
    }

    #[test]
    fn document_needs_pin_false_when_content_unchanged() {
        let blob = b"conteudo cifrado fake";
        let hash = crate::ipfs::keccak256_hex(blob);
        assert!(!document_needs_pin(blob, Some(&hash)));
    }

    #[test]
    fn document_needs_pin_true_when_content_changed() {
        let old_blob = b"conteudo antigo";
        let new_blob = b"conteudo novo, diferente";
        let old_hash = crate::ipfs::keccak256_hex(old_blob);
        assert!(document_needs_pin(new_blob, Some(&old_hash)));
    }
}

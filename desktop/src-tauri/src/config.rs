use keyring::Entry;
use std::path::{Path, PathBuf};

/// Retorna o diretório `.truthid` do usuário, criando-o se não existir.
///
/// Ordem: `$HOME` → (só no Windows) `%USERPROFILE%` → `/tmp` (Docker, CI).
/// No Windows o `HOME` normalmente não existe, e antes disso tudo caía em
/// `\tmp\.truthid` na raiz do disco, fora do perfil do usuário (P95, achado
/// da revisão de segurança do winget-pkgs). Se o diretório novo ainda não
/// existe e o antigo sim, ele é movido pra lá uma vez só.
pub(crate) fn truthid_dir() -> Result<PathBuf, String> {
    let dir = resolve_truthid_dir(
        std::env::var("HOME").ok(),
        std::env::var("USERPROFILE").ok(),
        cfg!(windows),
    );
    if cfg!(windows) {
        migrate_legacy_tmp_dir(&dir, &Path::new("/tmp").join(".truthid"));
    }
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn resolve_truthid_dir(home: Option<String>, userprofile: Option<String>, windows: bool) -> PathBuf {
    let non_empty = |v: Option<String>| v.filter(|s| !s.trim().is_empty());
    let base = non_empty(home)
        .or_else(|| if windows { non_empty(userprofile) } else { None })
        .unwrap_or_else(|| "/tmp".to_string());
    Path::new(&base).join(".truthid")
}

/// Move `legacy` pra `dir` se `dir` ainda não existe. Só renomeia (nunca
/// apaga nem sobrescreve): se falhar ou `dir` já existir, deixa tudo como
/// está — os dados antigos não se perdem.
fn migrate_legacy_tmp_dir(dir: &Path, legacy: &Path) {
    if dir == legacy || dir.exists() || !legacy.is_dir() {
        return;
    }
    if let Some(parent) = dir.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::rename(legacy, dir);
}

/// Retorna o caminho completo para um arquivo dentro de `$HOME/.truthid/`.
/// Ex: `truthid_file_path("device.key")` → `$HOME/.truthid/device.key`
pub(crate) fn truthid_file_path(name: &str) -> Result<PathBuf, String> {
    truthid_dir().map(|d| d.join(name))
}

/// Lê todo o conteúdo de um arquivo binário.
pub(crate) fn read_file(path: &Path) -> Result<Vec<u8>, String> {
    std::fs::read(path).map_err(|e| e.to_string())
}

/// Escreve dados binários em um arquivo, criando o diretório pai se necessário.
pub(crate) fn write_file(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(path, data).map_err(|e| e.to_string())
}

/// Como `write_file`, mas grava com permissão 0o600 (leitura/escrita só pro
/// dono) no Unix — usado pros fallbacks de segredo em texto plano que só
/// existem quando o keyring do SO não está disponível (`device.key`,
/// `vault.key`, `arweave_wallet.json`). Sem isso, o arquivo sai com o umask
/// padrão do sistema (tipicamente 0o644, mundo-legível). No Windows é
/// no-op — ACL de arquivo é outro mecanismo, fora de escopo; por isso o
/// fallback é sinalizado ao usuário (`plaintext_fallback_in_use`).
pub(crate) fn write_secret_file(path: &Path, data: &[u8]) -> Result<(), String> {
    write_file(path, data)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Lê o conteúdo de um arquivo de texto.
pub(crate) fn read_text(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| e.to_string())
}

/// Lê e desserializa um arquivo JSON. Retorna `T::default()` se o arquivo
/// não existir ou estiver vazio/inválido — mesmo comportamento dos
/// `unwrap_or_default` existentes em cada call site original.
pub(crate) fn load_json<T: serde::de::DeserializeOwned + Default>(path: &Path) -> T {
    let raw = std::fs::read_to_string(path).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

/// Serializa um valor como JSON pretty-printed e salva no arquivo.
pub(crate) fn save_json<T: serde::Serialize + ?Sized>(
    path: &Path,
    value: &T,
) -> Result<(), String> {
    let json = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    write_file(path, json.as_bytes())
}

/// Arquivos em texto plano que só existem quando o keyring do SO falhou
/// (fallback de `set_keyring_or_file`). `app_lock.enc` fica de fora: é um
/// blob já cifrado, não um segredo em claro.
const PLAINTEXT_FALLBACK_FILES: [&str; 4] = [
    "device.key",
    "vault.key",
    "arweave_wallet.json",
    "local_wallet.key",
];

/// `true` se algum segredo está guardado em arquivo de texto plano em vez do
/// keyring do SO — a UI usa pra avisar o usuário (P95, revisão de segurança
/// do winget-pkgs: o fallback era silencioso).
pub(crate) fn plaintext_fallback_in_use() -> bool {
    let Ok(dir) = truthid_dir() else {
        return false;
    };
    plaintext_fallback_in_dir(&dir)
}

fn plaintext_fallback_in_dir(dir: &Path) -> bool {
    PLAINTEXT_FALLBACK_FILES
        .iter()
        .any(|name| dir.join(name).is_file())
}

/// Lê um segredo de texto (chave hex, blob cifrado, JSON) do keyring do SO,
/// com fallback em arquivo — padrão repetido em `get_device_key_hex`
/// (`lib.rs`), `get_arweave_wallet` (`lib.rs`), `get_local_wallet_key_hex`
/// (`local_wallet.rs`) e `get_app_lock_blob_hex` (`app_lock.rs`) antes desta
/// extração (achado de reuso, P84 #9). Retorna `Ok(None)` quando não há
/// segredo em nenhum dos dois lugares — cabe a cada chamador decidir a
/// mensagem de "não encontrado" (elas variam: "gere uma primeiro", "bloqueio
/// não está habilitado", etc). Um erro de I/O real lendo o arquivo de
/// fallback ainda propaga como `Err`, não vira `None` silenciosamente.
///
/// Trata uma entrada de keyring vazia como "não existe" (achado real, P71):
/// `entry.get_password()` só falha (`Err`) se a entrada não existir — uma
/// entrada vazia é um `Ok` "válido" do ponto de vista do keyring, que antes
/// mascarava por completo o fallback em arquivo se não filtrada aqui.
pub(crate) fn get_keyring_or_file(
    service: &str,
    account: &str,
    path: &Path,
) -> Result<Option<String>, String> {
    if let Ok(entry) = Entry::new(service, account) {
        if let Ok(value) = entry.get_password() {
            if !value.trim().is_empty() {
                return Ok(Some(value));
            }
        }
    }

    if path.exists() {
        let value = read_text(path)?.trim().to_string();
        // Keyring voltou a funcionar: sobe o segredo pra lá e apaga o texto
        // plano (senão o aviso de P95 nunca some e a chave segue exposta).
        if !value.is_empty() {
            migrate_file_to_keyring(service, account, path, &value);
        }
        return Ok(Some(value));
    }

    Ok(None)
}

/// Tenta mover um segredo do arquivo de fallback pro keyring do SO. Só apaga
/// o arquivo depois de reler o valor do keyring e conferir que é idêntico;
/// qualquer falha deixa o arquivo como está (nada se perde).
pub(crate) fn migrate_file_to_keyring(service: &str, account: &str, path: &Path, value: &str) {
    migrate_file_secret(path, value, || {
        let Ok(entry) = Entry::new(service, account) else {
            return false;
        };
        entry.set_password(value).is_ok() && entry.get_password().is_ok_and(|v| v == value)
    });
}

fn migrate_file_secret(path: &Path, value: &str, store_and_verify: impl FnOnce() -> bool) {
    if !value.is_empty() && store_and_verify() {
        let _ = std::fs::remove_file(path);
    }
}

/// Grava um segredo de texto no keyring do SO; se o keyring não estiver
/// disponível (ex: Docker, daemon fora do ar), grava em arquivo com
/// `write_secret_file` (permissão 0o600). Par de `get_keyring_or_file`, mesma
/// extração (P84 #9).
pub(crate) fn set_keyring_or_file(
    service: &str,
    account: &str,
    path: &Path,
    value: &str,
) -> Result<(), String> {
    let saved = Entry::new(service, account)
        .and_then(|e| e.set_password(value))
        .is_ok();

    if !saved {
        write_secret_file(path, value.as_bytes())?;
    } else if path.exists() {
        // Sobra de um fallback anterior: o keyring agora tem o valor novo.
        let _ = std::fs::remove_file(path);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_truthid_dir_prefers_home_then_userprofile_on_windows_only() {
        let some = |s: &str| Some(s.to_string());
        assert_eq!(
            resolve_truthid_dir(some("/h"), some("C:/u"), true),
            Path::new("/h").join(".truthid")
        );
        assert_eq!(
            resolve_truthid_dir(None, some("C:/u"), true),
            Path::new("C:/u").join(".truthid")
        );
        assert_eq!(
            resolve_truthid_dir(some(" "), some("C:/u"), true),
            Path::new("C:/u").join(".truthid")
        );
        // Fora do Windows, USERPROFILE é ignorado.
        assert_eq!(
            resolve_truthid_dir(None, some("C:/u"), false),
            Path::new("/tmp").join(".truthid")
        );
        assert_eq!(
            resolve_truthid_dir(None, None, true),
            Path::new("/tmp").join(".truthid")
        );
    }

    #[test]
    fn migrate_legacy_moves_once_and_never_overwrites() {
        let root = std::env::temp_dir().join("truthid_config_migrate_test");
        let _ = std::fs::remove_dir_all(&root);
        let legacy = root.join("legacy");
        let dir = root.join("profile").join(".truthid");
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(legacy.join("vault.enc"), b"data").unwrap();

        migrate_legacy_tmp_dir(&dir, &legacy);
        assert_eq!(std::fs::read(dir.join("vault.enc")).unwrap(), b"data");
        assert!(!legacy.exists());

        // Diretório novo já existe: um legado recriado não sobrescreve nada.
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(legacy.join("vault.enc"), b"other").unwrap();
        migrate_legacy_tmp_dir(&dir, &legacy);
        assert_eq!(std::fs::read(dir.join("vault.enc")).unwrap(), b"data");
        assert!(legacy.exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn migrate_file_secret_deletes_only_after_verified_store() {
        let dir = std::env::temp_dir().join("truthid_config_migrate_secret_test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("vault.key");
        std::fs::write(&file, b"abc").unwrap();

        migrate_file_secret(&file, "abc", || false);
        assert!(file.exists(), "keyring falhou: arquivo deve ficar");

        migrate_file_secret(&file, "", || true);
        assert!(file.exists(), "valor vazio nunca migra");

        migrate_file_secret(&file, "abc", || true);
        assert!(!file.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn plaintext_fallback_detects_only_secret_files() {
        let dir = std::env::temp_dir().join("truthid_config_plaintext_fallback_test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(!plaintext_fallback_in_dir(&dir));

        // Blob já cifrado não conta como segredo em claro.
        std::fs::write(dir.join("app_lock.enc"), b"x").unwrap();
        assert!(!plaintext_fallback_in_dir(&dir));

        std::fs::write(dir.join("vault.key"), b"x").unwrap();
        assert!(plaintext_fallback_in_dir(&dir));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[cfg(unix)]
    fn write_secret_file_sets_0600_permissions() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join("truthid_config_write_secret_file_test");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("write_secret_file_sets_0600_permissions.secret");

        write_secret_file(&path, b"top-secret").unwrap();

        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        assert_eq!(std::fs::read(&path).unwrap(), b"top-secret");

        std::fs::remove_file(&path).ok();
    }
}

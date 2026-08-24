use std::path::{Path, PathBuf};

/// Retorna o diretório `$HOME/.truthid`, criando-o se não existir.
/// Fallback pra `/tmp/.truthid` quando `$HOME` não está definido (Docker, CI).
pub(crate) fn truthid_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
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
/// no-op — ACL de arquivo é outro mecanismo, fora de escopo.
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

#[cfg(test)]
mod tests {
    use super::*;

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

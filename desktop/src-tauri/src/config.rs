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

/// Lê o conteúdo de um arquivo de texto.
pub(crate) fn read_text(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| e.to_string())
}

/// Escreve uma string em um arquivo de texto.
pub(crate) fn write_text(path: &Path, text: &str) -> Result<(), String> {
    write_file(path, text.as_bytes())
}

/// Lê e desserializa um arquivo JSON. Retorna `T::default()` se o arquivo
/// não existir ou estiver vazio/inválido — mesmo comportamento dos
/// `unwrap_or_default` existentes em cada call site original.
pub(crate) fn load_json<T: serde::de::DeserializeOwned + Default>(path: &Path) -> T {
    let raw = std::fs::read_to_string(path).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

/// Serializa um valor como JSON pretty-printed e salva no arquivo.
pub(crate) fn save_json<T: serde::Serialize + ?Sized>(path: &Path, value: &T) -> Result<(), String> {
    let json = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    write_file(path, json.as_bytes())
}

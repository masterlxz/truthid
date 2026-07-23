use std::path::{Path, PathBuf};

/// Retorna o diretório `$HOME/.truthid`, criando-o se não existir.
/// Fallback pra `/tmp/.truthid` quando `$HOME` não está definido (Docker, CI).
pub(crate) fn truthid_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
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
    std::fs::write(path, json).map_err(|e| e.to_string())
}

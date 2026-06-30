use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct DeviceVaultPermission {
    pub pub_key: String,
    pub can_write: bool,
}

fn path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    std::path::Path::new(&home)
        .join(".truthid")
        .join("vault_permissions.json")
}

pub(crate) fn load() -> Vec<DeviceVaultPermission> {
    let p = path();
    if !p.exists() {
        return Vec::new();
    }
    let raw = std::fs::read_to_string(&p).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

pub(crate) fn set(pub_key: &str, can_write: bool) -> Result<(), String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    let mut perms = load();
    if let Some(p) = perms.iter_mut().find(|p| p.pub_key == pub_key) {
        p.can_write = can_write;
    } else {
        perms.push(DeviceVaultPermission {
            pub_key: pub_key.to_string(),
            can_write,
        });
    }
    std::fs::write(path(), serde_json::to_string_pretty(&perms).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

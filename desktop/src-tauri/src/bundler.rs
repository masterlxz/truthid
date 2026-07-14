use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Config do bundler Pimlico usado pra montar/enviar UserOperations ERC-4337
/// pela device key (sem Ledger) — mirror de `BundlerConfigService` no Mobile
/// (`mobile/lib/services/bundler_config_service.dart`), mesmo padrão de
/// persistência local de `ipfs::PinningProvider`
/// (`~/.truthid/pinning_providers.json`). Sem UI de configuração ainda — só
/// o suficiente pra configurar a chave manualmente uma vez e os testes
/// conseguirem rodar contra o bundler de verdade.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub(crate) struct BundlerConfig {
    pub api_key: String,
    pub network: String,
}

fn config_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    std::path::Path::new(&home)
        .join(".truthid")
        .join("bundler_config.json")
}

pub(crate) fn load_config() -> BundlerConfig {
    let path = config_path();
    if !path.exists() {
        return BundlerConfig::default();
    }
    let raw = std::fs::read_to_string(&path).unwrap_or_default();
    serde_json::from_str(&raw).unwrap_or_default()
}

pub(crate) fn save_config(config: &BundlerConfig) -> Result<(), String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = std::path::Path::new(&home).join(".truthid");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let json = serde_json::to_string_pretty(config).map_err(|e| e.to_string())?;
    std::fs::write(config_path(), json).map_err(|e| e.to_string())
}

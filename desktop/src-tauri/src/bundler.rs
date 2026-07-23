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

fn config_path() -> Result<PathBuf, String> {
    crate::config::truthid_dir().map(|d| d.join("bundler_config.json"))
}

pub(crate) fn load_config() -> BundlerConfig {
    let path = match config_path() {
        Ok(p) => p,
        Err(_) => return BundlerConfig::default(),
    };
    if !path.exists() {
        return BundlerConfig::default();
    }
    crate::config::load_json(&path)
}

pub(crate) fn save_config(config: &BundlerConfig) -> Result<(), String> {
    let path = config_path()?;
    crate::config::save_json(&path, config)
}
use serde::{Deserialize, Serialize};

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

pub(crate) fn load_config() -> BundlerConfig {
    let path = match crate::config::truthid_file_path("bundler_config.json") {
        Ok(p) => p,
        Err(_) => return BundlerConfig::default(),
    };
    if !path.exists() {
        return BundlerConfig::default();
    }
    crate::config::load_json(&path)
}

pub(crate) fn save_config(config: &BundlerConfig) -> Result<(), String> {
    let path = crate::config::truthid_file_path("bundler_config.json")?;
    crate::config::save_json(&path, config)
}
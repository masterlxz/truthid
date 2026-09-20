//! Camada de storage do Vault. Hoje só o Arweave publica (e o IPFS legado só
//! lê); o `GitStorageProvider` entra aqui. Ver `project/PENDING.md` (P89 e o
//! plano do Git) e a memória do debate.

mod arweave_provider;
pub(crate) mod pointer;

pub(crate) use arweave_provider::ArweaveProvider;
pub(crate) use pointer::PointerKind;

/// Um destino onde o Vault é publicado.
///
/// `publish` recebe o vault já carregado (e o muta: CIDs de documentos,
/// versão publicada) e devolve o ponteiro + `content_hash` que o chamador
/// grava on-chain via `VaultRegistry.updateVault`. Cada provider decide o
/// que é uma unidade de publicação — no Arweave, um blob por entrada mais um
/// manifesto; no Git, um commit.
///
/// Despacho estático (sem `dyn`): `async fn` em trait não é object-safe, e os
/// providers são poucos e conhecidos em tempo de compilação.
pub(crate) trait VaultStorageProvider {
    async fn publish(&self, vault: &mut crate::vault::Vault) -> Result<crate::PublishResult, String>;
}

//! Camada de storage do Vault. Hoje só o Arweave publica (e o IPFS legado só
//! lê); o `GitStorageProvider` entra aqui. Ver `project/PENDING.md` (P89 e o
//! plano do Git) e a memória do debate.

pub(crate) mod pointer;

pub(crate) use pointer::PointerKind;

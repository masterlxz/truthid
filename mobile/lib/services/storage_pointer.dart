/// Qual storage um ponteiro do `VaultRegistry` (ou um `cid` de entrada/
/// documento) referencia. Espelha `storage::PointerKind` (Rust) e
/// `pointerKind` (TS) — mantenha os três iguais.
///
/// - `ar://<txid>`  → Arweave
/// - `git:...`      → Git
/// - qualquer outro → CID IPFS legado, sem esquema (inclui esquema
///   desconhecido, que já caía no gateway IPFS antes disto existir)
///
/// Existe pra que nenhum call site repita `!startsWith('ar://')` como
/// sinônimo de "IPFS legado": com um terceiro backend, esse `!` passaria a
/// classificar como IPFS (e mostrar o banner de migração) um ponteiro que não é.
enum StoragePointerKind {
  arweave,
  git,
  legacyIpfs;

  static const arweavePrefix = 'ar://';
  static const gitPrefix = 'git:';

  static StoragePointerKind of(String pointer) {
    if (pointer.startsWith(arweavePrefix)) return arweave;
    if (pointer.startsWith(gitPrefix)) return git;
    return legacyIpfs;
  }
}

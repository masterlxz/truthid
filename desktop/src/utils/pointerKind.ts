/**
 * Qual storage um ponteiro do VaultRegistry referencia. Espelha
 * `storage::PointerKind` (Rust) e `StoragePointerKind` (Dart) — mantenha os
 * três iguais.
 *
 * - `ar://<txid>`  → Arweave
 * - `git:...`      → Git
 * - qualquer outro → CID IPFS legado, sem esquema (inclui esquema desconhecido,
 *   que já caía no gateway IPFS antes desta função existir)
 */
export type PointerKind = "arweave" | "git" | "legacy-ipfs";

export const ARWEAVE_PREFIX = "ar://";
export const GIT_PREFIX = "git:";

export function pointerKind(pointer: string): PointerKind {
  if (pointer.startsWith(ARWEAVE_PREFIX)) return "arweave";
  if (pointer.startsWith(GIT_PREFIX)) return "git";
  return "legacy-ipfs";
}

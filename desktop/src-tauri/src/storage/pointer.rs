//! Qual storage um ponteiro do `VaultRegistry` (ou um `cid` de entrada/documento)
//! referencia. O ponteiro é uma string opaca on-chain; o esquema dele é o que
//! diz onde o conteúdo mora:
//!
//! - `ar://<txid>`  → Arweave
//! - `git:...`      → Git (ponteiro cifrado, ver o plano do `GitStorageProvider`)
//! - qualquer outro → CID IPFS legado, sem esquema
//!
//! Existe pra que nenhum call site precise repetir `!starts_with("ar://")`
//! como sinônimo de "IPFS legado" — com um terceiro backend, esse `!` passaria
//! a classificar como IPFS um ponteiro que não é.

pub(crate) const ARWEAVE_PREFIX: &str = "ar://";
pub(crate) const GIT_PREFIX: &str = "git:";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PointerKind {
    Arweave,
    Git,
    LegacyIpfs,
}

impl PointerKind {
    /// Um esquema desconhecido cai em `LegacyIpfs`, o mesmo destino que ele
    /// já tinha antes desta enum existir (gateway IPFS, que vai falhar).
    pub(crate) fn of(pointer: &str) -> Self {
        if pointer.starts_with(ARWEAVE_PREFIX) {
            Self::Arweave
        } else if pointer.starts_with(GIT_PREFIX) {
            Self::Git
        } else {
            Self::LegacyIpfs
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arweave_pointer() {
        assert_eq!(PointerKind::of("ar://Abc123_-xyz"), PointerKind::Arweave);
    }

    #[test]
    fn git_pointer() {
        assert_eq!(PointerKind::of("git:AQID@0123456789abcdef0123456789abcdef01234567"), PointerKind::Git);
    }

    #[test]
    fn bare_cids_are_legacy_ipfs() {
        assert_eq!(
            PointerKind::of("QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"),
            PointerKind::LegacyIpfs
        );
        assert_eq!(
            PointerKind::of("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"),
            PointerKind::LegacyIpfs
        );
    }

    #[test]
    fn unknown_scheme_keeps_falling_into_legacy_ipfs() {
        assert_eq!(PointerKind::of("http://example.com/x"), PointerKind::LegacyIpfs);
        assert_eq!(PointerKind::of(""), PointerKind::LegacyIpfs);
    }

    #[test]
    fn prefix_match_is_case_sensitive_and_anchored() {
        // "AR://" e "xar://" não são Arweave — o esquema é literal.
        assert_eq!(PointerKind::of("AR://x"), PointerKind::LegacyIpfs);
        assert_eq!(PointerKind::of("xar://x"), PointerKind::LegacyIpfs);
        assert_eq!(PointerKind::of("mygit:x"), PointerKind::LegacyIpfs);
    }
}

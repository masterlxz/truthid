//! Provider Arweave do Vault (P87): cada entrada vira um blob cifrado próprio
//! no Arweave e o ponteiro on-chain aponta pra um manifesto pequeno
//! (`entryId -> {cid, contentHash, updatedAt}`).
//!
//! O corpo de `publish` é o que era `vault_publish` em `lib.rs`, movido sem
//! alteração de comportamento quando a abstração de provider foi criada.

use super::VaultStorageProvider;
use crate::{arweave, vault};

pub(crate) struct ArweaveProvider;

impl VaultStorageProvider for ArweaveProvider {
    async fn publish(&self, v: &mut vault::Vault) -> Result<crate::PublishResult, String> {
        for i in 0..v.entries.len() {
            let entry_id = v.entries[i].id.clone();
            let Some(doc) = &v.entries[i].document else {
                continue;
            };
            let Some(local_blob) = vault::read_document_blob(&entry_id)? else {
                continue;
            };
            if !vault::document_needs_pin(&local_blob, doc.content_hash.as_deref()) {
                continue;
            }
            let file_name = doc.file_name.clone();
            let mime_type = doc.mime_type.clone();
            let result = arweave::publish_document(&local_blob, &file_name, &mime_type).await?;
            let doc = v.entries[i].document.as_mut().expect("checked above");
            doc.cid = Some(result.cid);
            doc.content_hash = Some(result.content_hash);
            // Salva logo após cada documento pra não perder o CID de um publish
            // já pago em AR real se um documento seguinte falhar no meio do loop
            // (o AR gasto no anterior já está on-chain de qualquer forma).
            vault::save(v)?;
        }

        let changed = vault::changed_entries_from(v)?;
        let mut entry_refs: std::collections::HashMap<String, vault::ManifestEntryRef> =
            vault::load_last_manifest()?
                .map(|m| m.entries)
                .unwrap_or_default();

        for (id, kind) in &changed {
            match kind {
                vault::EntryDiffKind::Removed => {
                    entry_refs.remove(id);
                }
                vault::EntryDiffKind::Added | vault::EntryDiffKind::Modified => {
                    let entry = v
                        .entries
                        .iter()
                        .find(|e| &e.id == id)
                        .expect("changed id must exist in current vault");
                    let blob = vault::write_entry_blob(id, entry)?;
                    let result = arweave::publish_vault_entry(&blob).await?;
                    entry_refs.insert(
                        id.clone(),
                        vault::ManifestEntryRef {
                            cid: result.cid,
                            content_hash: result.content_hash,
                            updated_at: entry.updated_at,
                        },
                    );
                }
            }
        }

        let manifest = vault::build_manifest(v, &entry_refs);
        let manifest_blob = vault::encrypt_manifest(&manifest)?;
        let result = arweave::publish_manifest(&manifest_blob).await?;
        vault::save_last_manifest(&manifest)?;

        // Fase 15.8: normaliza card_number/cvv pra texto plano antes de marcar
        // publicado — crítico pra corretude do diff de pending_changes(), que
        // sempre compara contra load() (também em claro). Sem isso, o snapshot
        // guardaria os campos cifrados (nonce novo a cada save), e qualquer
        // vault com cartão veria "pendência fantasma" pra sempre.
        vault::decrypt_card_fields_in_place(v);
        vault::mark_published(v.version, v)?;
        Ok(result)
    }
}

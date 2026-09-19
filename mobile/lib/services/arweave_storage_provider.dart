import 'dart:typed_data';

import 'arweave_client.dart';
import 'ipfs_gateway_client.dart';
import 'vault_repository.dart';
import 'vault_storage_provider.dart';

/// Provider Arweave do Vault (P87): cada entrada vira um blob cifrado próprio
/// e o ponteiro on-chain aponta pra um manifesto pequeno
/// (`entryId -> {cid, contentHash, updatedAt}`).
///
/// O corpo é o que era `VaultPublishService.publish`, movido sem alteração de
/// comportamento quando a abstração de provider foi criada. A leitura
/// (`fetch`) continua no `IpfsGatewayClient`, que já resolve `ar://` e IPFS.
class ArweaveStorageProvider implements VaultStorageProvider {
  final VaultRepository _repository;
  final ArweaveVaultPublisher _publisher;
  final IpfsGatewayClient _gateway;

  ArweaveStorageProvider({
    required this._repository,
    ArweaveVaultPublisher? publisher,
    IpfsGatewayClient? gateway,
  })  : _publisher = publisher ?? ArweaveVaultPublisher(),
        _gateway = gateway ?? IpfsGatewayClient();

  @override
  Future<Uint8List> fetch(String pointer) => _gateway.fetch(pointer);

  @override
  Future<void> publishPendingDocuments() async {
    // Fase 15.7: publica separadamente o conteúdo (cache local cifrado) de
    // cada documento que ainda não tem cid ou cujo conteúdo local mudou
    // desde a última publicação — o vault carrega só o ponteiro
    // (cid/contentHash), nunca o conteúdo do documento em si, então
    // documentos grandes não inflam o sync de edições não relacionadas (ver
    // project/PHASE.md, 15.7).
    for (final entry in await _repository.listEntries()) {
      final doc = entry.document;
      if (doc == null) continue;
      final localBlob = await _repository.readDocumentBlob(entry.id);
      if (localBlob == null) continue;
      if (_repository.documentNeedsPin(localBlob, doc.contentHash)) {
        final result =
            await _publisher.publishDocument(localBlob, doc.fileName, doc.mimeType);
        await _repository.setDocumentPinInfo(
          entry.id,
          cid: result.cid,
          contentHash: result.contentHash,
        );
      }
    }
  }

  @override
  Future<StagedVaultPublish> publishVault(VaultPublishSnapshot snapshot) async {
    // Vault por-entrada: publica só as entradas que mudaram desde o último
    // snapshot publicado (blob próprio por entrada no Arweave, mesmo padrão
    // dos documentos), parte do último manifesto conhecido pra manter o
    // cid/hash das entradas inalteradas.
    final changed = await _repository.diffEntriesSinceLastPublish();
    final lastManifest = await _repository.loadLastManifest();
    final entryRefs =
        Map<String, ManifestEntryRef>.from(lastManifest?.entries ?? {});
    if (changed.isNotEmpty) {
      final entriesById = {for (final e in snapshot.entries) e.id: e};
      for (final change in changed.entries) {
        if (change.value == EntryDiffKind.removed) {
          entryRefs.remove(change.key);
          continue;
        }
        final entry = entriesById[change.key];
        if (entry == null) continue; // não deveria acontecer
        final blob = await _repository.writeEntryBlob(change.key, entry);
        final result = await _publisher.publishVaultEntry(blob);
        entryRefs[change.key] = ManifestEntryRef(
          cid: result.cid,
          contentHash: result.contentHash,
          updatedAt: entry.updatedAt.millisecondsSinceEpoch ~/ 1000,
        );
      }
    }

    final manifest = VaultManifest(
      version: 1,
      vaultVersion: snapshot.version,
      entries: entryRefs,
      profileNames: snapshot.profileNames,
      devicePermissions: snapshot.devicePermissions,
    );
    final manifestBlob = await _repository.encryptManifestBlob(manifest);
    final published = await _publisher.publishManifest(manifestBlob);

    return StagedVaultPublish(
      pointer: published.cid,
      contentHash: published.contentHash,
      commitLocalState: () => _repository.saveLastManifest(manifest),
    );
  }
}

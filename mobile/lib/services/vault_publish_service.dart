import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'arweave_client.dart';
import 'session_creator.dart';
import 'vault_repository.dart';

class VaultPublishResult {
  final String cid;
  final String contentHash;
  final String? transactionHash;

  const VaultPublishResult({
    required this.cid,
    required this.contentHash,
    this.transactionHash,
  });
}

// Orquestra a publicação do vault a partir do Mobile: publica no Arweave só
// as entradas que mudaram desde o último snapshot publicado (blob cifrado
// por entrada) + um manifesto pequeno (entryId -> cid/contentHash) → publica
// CID+hash do MANIFESTO on-chain via UserOperation
// (SessionCreator.updateVault) → marca a versão como publicada. Mirror do
// par `useVaultPublish.ts` (Desktop) + comando Tauri `vault_publish`, só que
// numa função só — o Mobile não tem a mesma separação Tauri/JS. Ver
// project/INDEX.md, Sessão 97. Corte direto pro Arweave sem fallback pro
// IPFS (mesmo padrão do Desktop, Sessões 187-189).
class VaultPublishService {
  final VaultRepository _repository;
  final ArweaveVaultPublisher _arweavePublisher;
  final SessionCreator _sessionCreator;

  VaultPublishService({
    required this._sessionCreator,
    VaultRepository? repository,
    ArweaveVaultPublisher? arweavePublisher,
  })  : _repository = repository ?? VaultRepository(),
        _arweavePublisher = arweavePublisher ?? ArweaveVaultPublisher();

  Future<VaultPublishResult> publish(EthereumAddress smartAccountAddress) async {
    // Mirror do guard do Desktop (vault_publish, lib.rs) — sem isso, um
    // device sem cache local (ex: pareamento novo que falhou ao sincronizar)
    // publicaria um vault vazio por cima do vault de verdade on-chain.
    if (!await _repository.hasLocalVault()) {
      throw Exception(
        'vault ainda não existe localmente — adicione ao menos uma entrada '
        'antes de publicar',
      );
    }

    // Fase 15.7: antes de publicar o blob principal, publica separadamente o
    // conteúdo (cache local cifrado) de cada documento que ainda não tem
    // cid ou cujo conteúdo local mudou desde a última publicação — o blob
    // do vault carrega só o ponteiro (cid/contentHash), nunca o conteúdo do
    // documento em si, então documentos grandes não inflam o sync de
    // edições não relacionadas (ver project/PHASE.md, 15.7).
    for (final entry in await _repository.listEntries()) {
      final doc = entry.document;
      if (doc == null) continue;
      final localBlob = await _repository.readDocumentBlob(entry.id);
      if (localBlob == null) continue;
      if (_repository.documentNeedsPin(localBlob, doc.contentHash)) {
        final result =
            await _arweavePublisher.publishDocument(localBlob, doc.fileName, doc.mimeType);
        await _repository.setDocumentPinInfo(
          entry.id,
          cid: result.cid,
          contentHash: result.contentHash,
        );
      }
    }

    // Snapshot do estado local ANTES de qualquer chamada de rede — mesma
    // cautela contra TOCTOU já documentada (M3, Sessão 153): uma edição
    // concorrente feita durante a publicação (ex: no meio do `updateVault`
    // on-chain, que pode levar segundos) não pode ser confundida com o que
    // de fato foi publicado. `version`/`snapshotBlob` vão pro `markPublished`
    // no final tal como capturados aqui, nunca relidos depois do publish.
    final version = await _repository.currentVersion();
    final snapshotBlob = await _repository.readRawBlob();
    final entries = await _repository.listEntries();
    final profileNames = await _repository.listProfileNames();
    final devicePermissions = await _repository.listDevicePermissions();

    // Vault por-entrada: publica só as entradas que mudaram desde o último
    // snapshot publicado (blob próprio por entrada no Arweave, mesmo padrão
    // dos documentos acima), parte do último manifesto conhecido pra manter
    // o cid/hash das entradas inalteradas.
    final changed = await _repository.diffEntriesSinceLastPublish();
    final lastManifest = await _repository.loadLastManifest();
    final entryRefs =
        Map<String, ManifestEntryRef>.from(lastManifest?.entries ?? {});
    if (changed.isNotEmpty) {
      final entriesById = {for (final e in entries) e.id: e};
      for (final change in changed.entries) {
        if (change.value == EntryDiffKind.removed) {
          entryRefs.remove(change.key);
          continue;
        }
        final entry = entriesById[change.key];
        if (entry == null) continue; // não deveria acontecer
        final blob = await _repository.writeEntryBlob(change.key, entry);
        final result = await _arweavePublisher.publishVaultEntry(blob);
        entryRefs[change.key] = ManifestEntryRef(
          cid: result.cid,
          contentHash: result.contentHash,
          updatedAt: entry.updatedAt.millisecondsSinceEpoch ~/ 1000,
        );
      }
    }

    final manifest = VaultManifest(
      version: 1,
      vaultVersion: version,
      entries: entryRefs,
      profileNames: profileNames,
      devicePermissions: devicePermissions,
    );
    final manifestBlob = await _repository.encryptManifestBlob(manifest);
    final publishResult = await _arweavePublisher.publishManifest(manifestBlob);

    final txResult = await _sessionCreator.updateVault(
      smartAccountAddress: smartAccountAddress,
      cid: publishResult.cid,
      contentHashHex: publishResult.contentHash,
    );

    await _repository.saveLastManifest(manifest);
    await _repository.markPublished(version, snapshotBlob);

    return VaultPublishResult(
      cid: publishResult.cid,
      contentHash: publishResult.contentHash,
      transactionHash: txResult.transactionHash,
    );
  }
}

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

// Orquestra a publicação do vault a partir do Mobile: lê o blob local cru
// (já cifrado) → publica no Arweave → publica CID+hash on-chain via
// UserOperation (SessionCreator.updateVault) → marca a versão como
// publicada. Mirror do par `useVaultPublish.ts` (Desktop) + comando Tauri
// `vault_publish`, só que numa função só — o Mobile não tem a mesma
// separação Tauri/JS. Ver project/INDEX.md, Sessão 97. Corte direto pro
// Arweave sem fallback pro IPFS (mesmo padrão do Desktop, Sessões 187-189).
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

    final version = await _repository.currentVersion();
    final blob = await _repository.readRawBlob();
    final publishResult = await _arweavePublisher.publishVaultBlob(blob);

    final txResult = await _sessionCreator.updateVault(
      smartAccountAddress: smartAccountAddress,
      cid: publishResult.cid,
      contentHashHex: publishResult.contentHash,
    );

    await _repository.markPublished(version, blob);

    return VaultPublishResult(
      cid: publishResult.cid,
      contentHash: publishResult.contentHash,
      transactionHash: txResult.transactionHash,
    );
  }
}

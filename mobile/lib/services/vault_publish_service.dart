import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'arweave_client.dart';
import 'arweave_storage_provider.dart';
import 'session_creator.dart';
import 'vault_repository.dart';
import 'vault_storage_provider.dart';

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

// Orquestra a publicação do vault a partir do Mobile: pede ao provider de
// storage (hoje o Arweave: só as entradas que mudaram desde o último snapshot
// + um manifesto pequeno) → publica o ponteiro+hash que ele devolve on-chain
// via UserOperation (SessionCreator.updateVault) → só então grava o estado
// local de "publicado". Mirror do par `useVaultPublish.ts` (Desktop) + comando
// Tauri `vault_publish`, só que numa função só — o Mobile não tem a mesma
// separação Tauri/JS. Ver project/INDEX.md, Sessão 97. Corte direto pro
// Arweave sem fallback pro IPFS (mesmo padrão do Desktop, Sessões 187-189).
//
// O que é publicar (blobs por entrada, manifesto, commit...) é decisão do
// [VaultStorageProvider]; este serviço só garante a ordem e o snapshot.
class VaultPublishService {
  final VaultRepository _repository;
  final SessionCreator _sessionCreator;
  late final VaultStorageProvider _storage;

  VaultPublishService({
    required this._sessionCreator,
    VaultRepository? repository,
    ArweaveVaultPublisher? arweavePublisher,
    VaultStorageProvider? storageProvider,
  }) : _repository = repository ?? VaultRepository() {
    // Único provider por enquanto; a escolha por identidade entra com o Git.
    _storage = storageProvider ??
        ArweaveStorageProvider(
          repository: _repository,
          publisher: arweavePublisher,
        );
  }

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

    // Antes do snapshot, de propósito: publicar o conteúdo dos documentos
    // grava cid/contentHash no vault local, e o snapshot precisa já refletir
    // isso (senão o `markPublished` final deixaria essa mudança "pendente").
    await _storage.publishPendingDocuments();

    // Snapshot do estado local ANTES de qualquer chamada de rede — mesma
    // cautela contra TOCTOU já documentada (M3, Sessão 153): uma edição
    // concorrente feita durante a publicação (ex: no meio do `updateVault`
    // on-chain, que pode levar segundos) não pode ser confundida com o que
    // de fato foi publicado. `version`/`rawBlob` vão pro `markPublished` no
    // final tal como capturados aqui, nunca relidos depois do publish.
    final snapshot = VaultPublishSnapshot(
      version: await _repository.currentVersion(),
      rawBlob: await _repository.readRawBlob(),
      entries: await _repository.listEntries(),
      profileNames: await _repository.listProfileNames(),
      devicePermissions: await _repository.listDevicePermissions(),
    );

    final staged = await _storage.publishVault(snapshot);

    final txResult = await _sessionCreator.updateVault(
      smartAccountAddress: smartAccountAddress,
      cid: staged.pointer,
      contentHashHex: staged.contentHash,
    );

    await staged.commitLocalState();
    await _repository.markPublished(snapshot.version, snapshot.rawBlob);

    return VaultPublishResult(
      cid: staged.pointer,
      contentHash: staged.contentHash,
      transactionHash: txResult.transactionHash,
    );
  }
}

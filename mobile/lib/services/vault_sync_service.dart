import 'package:web3dart/crypto.dart';

import 'blockchain_service.dart';
import 'ipfs_gateway_client.dart';
import 'storage_pointer.dart';
import 'vault_key_service.dart';
import 'vault_repository.dart';

enum VaultSyncStatus {
  synced,
  noVaultPublished,
  noVaultKey,
  offlineUsingCache,
  syncFailedNoCache,
}

class VaultSyncOutcome {
  final VaultSyncStatus status;
  final List<VaultEntry> entries;
  /// Nomes de perfis criados pelo usuário no Desktop (ver project/INDEX.md,
  /// Sessão 97) — vazio quando o sync não chegou a ler o vault (ex: sem chave,
  /// sem vault publicado, falha sem cache).
  final List<String> profileNames;
  final DateTime? updatedAt; // on-chain updatedAt, só quando status == synced
  final String? error; // motivo, pros banners de offline/falha
  /// true quando status == synced e o cid on-chain ainda é do esquema IPFS
  /// antigo (sem prefixo "ar://") — sem pinning dedicado desde a Sessão 193,
  /// um device novo sem cache falha ao carregar esse cid (achado real,
  /// Sessão 194). Sinaliza pra UI oferecer republish proativo, já que só um
  /// device com cache (como este, que chegou até `synced`) consegue migrar.
  final bool legacyIpfsCid;

  const VaultSyncOutcome({
    required this.status,
    required this.entries,
    this.profileNames = const [],
    this.updatedAt,
    this.error,
    this.legacyIpfsCid = false,
  });
}

// Hash do blob baixado não bate com o contentHash on-chain. Nunca deve ser
// tratada como sucesso — sempre cai pro fallback de cache local (ver sync()).
class VaultHashMismatchException implements Exception {
  final String message;
  const VaultHashMismatchException(this.message);
  @override
  String toString() => message;
}

// Orquestra a leitura do vault publicado: on-chain (VaultRegistry) → IPFS
// (blob cifrado) → verificação de integridade (keccak256 contra o
// contentHash on-chain) → decifra (via VaultRepository, que já sabe derivar
// a vault key). Nunca decifra/exibe conteúdo cujo hash não bateu — cai pro
// cache local nesse caso.
class VaultSyncService {
  VaultSyncService({
    BlockchainService? blockchainService,
    IpfsGatewayClient? gatewayClient,
    VaultKeyService? vaultKeyService,
    VaultRepository? repository,
  })  : _blockchain = blockchainService ?? BlockchainService(),
        _gateway = gatewayClient ?? IpfsGatewayClient(),
        _vaultKeyService = vaultKeyService ?? VaultKeyService(),
        _repository = repository ?? VaultRepository();

  final BlockchainService _blockchain;
  final IpfsGatewayClient _gateway;
  final VaultKeyService _vaultKeyService;
  final VaultRepository _repository;

  Future<VaultSyncOutcome> sync(BigInt identityId) async {
    // Checagem local, sem rede: device pareado que nunca recebeu a vault key
    // via ECIES no pareamento ganha uma mensagem acionável (re-parear) em vez
    // de um erro genérico de decifra mais adiante.
    if (!await _vaultKeyService.hasVaultKey()) {
      return const VaultSyncOutcome(
        status: VaultSyncStatus.noVaultKey,
        entries: [],
      );
    }

    // Fecha o gap de rotação de DEK: se outro device revogou alguém e
    // redistribuiu uma chave nova (ver ManageDevices.tsx no Desktop), este
    // device só descobre reconsultando `deviceVaultKeys` — nada além do
    // fluxo de pareamento fazia isso antes. Best-effort, reaproveitando o
    // ciclo de sync já existente em vez de um polling dedicado: se falhar
    // (offline, etc.) segue com a chave já cacheada, que continua válida
    // até aqui.
    try {
      await _vaultKeyService.tryRecoverFromChain(_blockchain);
    } catch (_) {
      // Não crítico — mesmo raciocínio do fallback de cache mais abaixo.
    }

    bool hasVault;
    try {
      hasVault = await _blockchain.hasVault(identityId);
    } catch (e) {
      return _fallbackToCache('Failed to check vault status: $e');
    }

    if (!hasVault) {
      return const VaultSyncOutcome(
        status: VaultSyncStatus.noVaultPublished,
        entries: [],
      );
    }

    VaultRef? ref;
    try {
      ref = await _blockchain.getVault(identityId);

      // O cache local pode ter mudanças escritas neste device e ainda não
      // publicadas (ver Sessão 97/124-125, VaultScreen chama sync() toda vez
      // que a tela recarrega). Sobrescrever incondicionalmente com o blob
      // on-chain apagaria essas mudanças sempre que o fetch tivesse sucesso —
      // só puxa do chain quando ele realmente está à frente do cache local.
      int localVersion;
      try {
        localVersion = await _repository.currentVersion();
      } catch (_) {
        // Cache local ilegível com a chave atual: outro device rotacionou a
        // DEK (P89/P56) e `tryRecoverFromChain` acima já trocou a chave.
        // Trata como device sem cache — puxa o vault novo do chain — em vez
        // de cair no fallback, que também não consegue ler esse cache.
        await _repository.setAsideUnreadableLocalCache();
        localVersion = 0;
      }
      if (ref.version <= localVersion) {
        // Local já reflete (ou está à frente d)o on-chain. Só quando as duas
        // versões batem exatamente é seguro marcar como "publicado até aqui"
        // — se local estiver à frente (mudanças pendentes deste device),
        // isso ficaria pra pendingChanges() continuar contando certo (ver
        // achado da Sessão 130: sem isso, um device que nunca publicou nada
        // localmente mas já nasceu sincronizado com a versão on-chain atual
        // mostrava "pending changes" fantasma).
        if (ref.version == localVersion) {
          final localBlob = await _repository.readRawBlob();
          await _repository.markPublished(ref.version, localBlob);
        }
        final entries = await _repository.listEntries();
        final profileNames = await _repository.listProfileNames();
        return VaultSyncOutcome(
          status: VaultSyncStatus.synced,
          entries: entries,
          profileNames: profileNames,
          updatedAt: ref.updatedAt,
          legacyIpfsCid: StoragePointerKind.of(ref.cid) == StoragePointerKind.legacyIpfs,
        );
      }

      final bytes = await _gateway.fetch(ref.cid);

      final digest = bytesToHex(keccak256(bytes), include0x: true);
      if (digest.toLowerCase() != ref.contentHashHex.toLowerCase()) {
        throw VaultHashMismatchException(
          'Downloaded blob hash ($digest) does not match on-chain contentHash (${ref.contentHashHex})',
        );
      }

      final manifest = await _repository.tryDecodeManifest(bytes);
      if (manifest == null) {
        // Blob legado (vault inteiro) — comportamento exatamente igual ao
        // de sempre, sem passar pelo caminho de manifesto abaixo.
        await _repository.overwriteCache(bytes);
        // Achado da Sessão 130: puxar uma versão mais nova doutro device sem
        // marcar como publicada deixava pendingChanges() (que compara contra
        // o marcador local de "última publicada por este device") achando
        // que essa versão ainda estava pendente — "pending changes" fantasma
        // no Mobile depois de sincronizar algo publicado pelo Desktop.
        await _repository.markPublished(ref.version, bytes);
        final entries = await _repository.listEntries();
        final profileNames = await _repository.listProfileNames();
        return VaultSyncOutcome(
          status: VaultSyncStatus.synced,
          entries: entries,
          profileNames: profileNames,
          updatedAt: ref.updatedAt,
          legacyIpfsCid: StoragePointerKind.of(ref.cid) == StoragePointerKind.legacyIpfs,
        );
      }

      // Manifesto: busca+verifica+decifra só as entradas cujo cid/contentHash
      // mudou desde o último manifesto conhecido por este device — nunca
      // sobrescreve o cache local de uma vez só (ao contrário do caminho
      // legado acima), então uma falha no meio (rede caiu buscando 1
      // entrada) cai no fallback sem corromper nada do que já estava bom.
      final lastManifest = await _repository.loadLastManifest();
      final changedIds =
          _repository.manifestChangedEntryIds(manifest, lastManifest);
      for (final id in changedIds) {
        final entryRef = manifest.entries[id]!;
        final entryBytes = await _gateway.fetch(entryRef.cid);
        final entryDigest = bytesToHex(keccak256(entryBytes), include0x: true);
        if (entryDigest.toLowerCase() != entryRef.contentHash.toLowerCase()) {
          throw VaultHashMismatchException(
            'Downloaded entry blob hash ($entryDigest) does not match manifest contentHash (${entryRef.contentHash}) for entry $id',
          );
        }
        await _repository.cacheEntryBlobRaw(id, entryBytes);
      }
      await _repository.reassembleFromManifest(manifest,
          changedEntryIds: changedIds);
      await _repository.saveLastManifest(manifest);
      final rebuiltBlob = await _repository.readRawBlob();
      await _repository.markPublished(ref.version, rebuiltBlob);
      final entries = await _repository.listEntries();
      final profileNames = await _repository.listProfileNames();
      return VaultSyncOutcome(
        status: VaultSyncStatus.synced,
        entries: entries,
        profileNames: profileNames,
        updatedAt: ref.updatedAt,
        legacyIpfsCid: false,
      );
    } catch (e) {
      // `ref` só fica disponível aqui quando o fetch/hash-check falhou depois
      // de já ler a referência on-chain (não quando `getVault` em si falhou)
      // — o suficiente pro cenário real (P51): device sem cache tentando
      // resolver um vault que já leu a ref, mas que aponta pro esquema IPFS
      // legado sem pinning dedicado.
      return _fallbackToCache(
        '$e',
        legacyIpfsCid: ref != null && StoragePointerKind.of(ref.cid) == StoragePointerKind.legacyIpfs,
      );
    }
  }

  Future<VaultSyncOutcome> _fallbackToCache(
    String error, {
    bool legacyIpfsCid = false,
  }) async {
    try {
      final entries = await _repository.listEntries();
      if (entries.isNotEmpty) {
        final profileNames = await _repository.listProfileNames();
        return VaultSyncOutcome(
          status: VaultSyncStatus.offlineUsingCache,
          entries: entries,
          profileNames: profileNames,
          error: error,
          legacyIpfsCid: legacyIpfsCid,
        );
      }
    } catch (_) {
      // cache corrompido/ilegível — trata igual a "sem cache" abaixo
    }
    return VaultSyncOutcome(
      status: VaultSyncStatus.syncFailedNoCache,
      entries: const [],
      error: error,
      legacyIpfsCid: legacyIpfsCid,
    );
  }
}

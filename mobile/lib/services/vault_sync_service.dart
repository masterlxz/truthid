import 'package:web3dart/crypto.dart';

import 'blockchain_service.dart';
import 'ipfs_gateway_client.dart';
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
  /// Nomes de perfis criados pelo usuário no Desktop (ver PROJECT_STATE.md,
  /// Sessão 97) — vazio quando o sync não chegou a ler o vault (ex: sem chave,
  /// sem vault publicado, falha sem cache).
  final List<String> profileNames;
  final DateTime? updatedAt; // on-chain updatedAt, só quando status == synced
  final String? error; // motivo, pros banners de offline/falha

  const VaultSyncOutcome({
    required this.status,
    required this.entries,
    this.profileNames = const [],
    this.updatedAt,
    this.error,
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

    try {
      final ref = await _blockchain.getVault(identityId);

      // O cache local pode ter mudanças escritas neste device e ainda não
      // publicadas (ver Sessão 97/124-125, VaultScreen chama sync() toda vez
      // que a tela recarrega). Sobrescrever incondicionalmente com o blob
      // on-chain apagaria essas mudanças sempre que o fetch tivesse sucesso —
      // só puxa do chain quando ele realmente está à frente do cache local.
      final localVersion = await _repository.currentVersion();
      if (ref.version <= localVersion) {
        final entries = await _repository.listEntries();
        final profileNames = await _repository.listProfileNames();
        return VaultSyncOutcome(
          status: VaultSyncStatus.synced,
          entries: entries,
          profileNames: profileNames,
          updatedAt: ref.updatedAt,
        );
      }

      final bytes = await _gateway.fetch(ref.cid);

      final digest = bytesToHex(keccak256(bytes), include0x: true);
      if (digest.toLowerCase() != ref.contentHashHex.toLowerCase()) {
        throw VaultHashMismatchException(
          'Downloaded blob hash ($digest) does not match on-chain contentHash (${ref.contentHashHex})',
        );
      }

      await _repository.overwriteCache(bytes);
      final entries = await _repository.listEntries();
      final profileNames = await _repository.listProfileNames();
      return VaultSyncOutcome(
        status: VaultSyncStatus.synced,
        entries: entries,
        profileNames: profileNames,
        updatedAt: ref.updatedAt,
      );
    } catch (e) {
      return _fallbackToCache('$e');
    }
  }

  Future<VaultSyncOutcome> _fallbackToCache(String error) async {
    try {
      final entries = await _repository.listEntries();
      if (entries.isNotEmpty) {
        final profileNames = await _repository.listProfileNames();
        return VaultSyncOutcome(
          status: VaultSyncStatus.offlineUsingCache,
          entries: entries,
          profileNames: profileNames,
          error: error,
        );
      }
    } catch (_) {
      // cache corrompido/ilegível — trata igual a "sem cache" abaixo
    }
    return VaultSyncOutcome(
      status: VaultSyncStatus.syncFailedNoCache,
      entries: const [],
      error: error,
    );
  }
}

import 'dart:typed_data';

import 'vault_blob_fetcher.dart';
import 'vault_repository.dart';

/// Estado local capturado por `VaultPublishService` **antes** de qualquer
/// chamada de rede (fix de TOCTOU do M3, Sessão 153): uma edição concorrente
/// durante a publicação não pode ser confundida com o que foi publicado.
/// `version` e `rawBlob` vão pro `markPublished` no fim, tal como capturados.
class VaultPublishSnapshot {
  final int version;
  final Uint8List rawBlob;
  final List<VaultEntry> entries;
  final List<String> profileNames;
  final List<VaultDevicePermission> devicePermissions;

  const VaultPublishSnapshot({
    required this.version,
    required this.rawBlob,
    required this.entries,
    required this.profileNames,
    required this.devicePermissions,
  });
}

/// Resultado de publicar o vault num provider: o ponteiro + hash que o
/// chamador grava on-chain, e o que o provider ainda precisa gravar
/// **localmente** depois que o `updateVault` on-chain der certo.
///
/// `commitLocalState` fica separado de propósito: se o `updateVault` falhar,
/// o provider não pode ter registrado a publicação como feita.
class StagedVaultPublish {
  final String pointer;
  final String contentHash;
  final Future<void> Function() commitLocalState;

  const StagedVaultPublish({
    required this.pointer,
    required this.contentHash,
    required this.commitLocalState,
  });
}

/// Um destino onde o Vault é publicado e de onde é lido. Espelha o trait
/// `VaultStorageProvider` do Desktop (`storage/mod.rs`): cada provider decide
/// o que é uma unidade de publicação — no Arweave, um blob por entrada mais
/// um manifesto; no Git, um commit.
abstract interface class VaultStorageProvider implements VaultBlobFetcher {
  /// Publica o conteúdo dos documentos que ainda não têm ponteiro (ou cujo
  /// conteúdo local mudou) e grava o ponteiro no vault local. Roda **antes**
  /// da captura do [VaultPublishSnapshot], porque muda o vault local.
  Future<void> publishPendingDocuments();

  /// Publica o vault a partir do [snapshot]. Não grava nada local que
  /// signifique "publicado": isso é [StagedVaultPublish.commitLocalState].
  Future<StagedVaultPublish> publishVault(VaultPublishSnapshot snapshot);
}

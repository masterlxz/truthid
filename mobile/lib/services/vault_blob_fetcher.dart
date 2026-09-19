import 'dart:typed_data';

/// Lê um blob a partir de um ponteiro de storage (o `cid` de um
/// `VaultRegistry`, de uma entrada ou de um documento).
///
/// Arquivo próprio, sem imports, pra `IpfsGatewayClient` (que o
/// `VaultRepository` importa) poder implementá-lo sem criar ciclo com
/// `vault_storage_provider.dart`, que importa os tipos do repositório.
abstract interface class VaultBlobFetcher {
  Future<Uint8List> fetch(String pointer);
}

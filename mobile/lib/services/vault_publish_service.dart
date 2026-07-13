import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'ipfs_pin_client.dart';
import 'pinning_provider_service.dart';
import 'session_creator.dart';
import 'vault_repository.dart';

class VaultPublishResult {
  final String cid;
  final String contentHash;
  final List<String> providersOk;
  final List<String> providersFailed;
  final String? transactionHash;

  const VaultPublishResult({
    required this.cid,
    required this.contentHash,
    required this.providersOk,
    required this.providersFailed,
    this.transactionHash,
  });
}

// Orquestra a publicação do vault a partir do Mobile: lê o blob local cru
// (já cifrado) → pina nos providers IPFS configurados → publica CID+hash
// on-chain via UserOperation (SessionCreator.updateVault) → marca a versão
// como publicada. Mirror do par `useVaultPublish.ts` (Desktop) + comando
// Tauri `vault_publish`, só que numa função só — o Mobile não tem a mesma
// separação Tauri/JS. Ver PROJECT_STATE.md, Sessão 97.
class VaultPublishService {
  final VaultRepository _repository;
  final IpfsPinClient _pinClient;
  final PinningProviderService _providerService;
  final SessionCreator _sessionCreator;

  VaultPublishService({
    required SessionCreator sessionCreator,
    VaultRepository? repository,
    IpfsPinClient? pinClient,
    PinningProviderService? providerService,
  })  : _sessionCreator = sessionCreator,
        _repository = repository ?? VaultRepository(),
        _pinClient = pinClient ?? IpfsPinClient(),
        _providerService = providerService ?? PinningProviderService();

  Future<VaultPublishResult> publish(EthereumAddress smartAccountAddress) async {
    final providers = await _providerService.load();
    if (providers.isEmpty) {
      throw Exception(
        'Nenhum provider de pin configurado — configure ao menos um Kubo local.',
      );
    }

    final version = await _repository.currentVersion();
    final blob = await _repository.readRawBlob();
    // pinVault já lança se nenhum Kubo aceitar o upload — um PinResult
    // retornado sempre tem pelo menos um provider em providersOk.
    final pinResult = await _pinClient.pinVault(blob, providers);

    final txResult = await _sessionCreator.updateVault(
      smartAccountAddress: smartAccountAddress,
      cid: pinResult.cid,
      contentHashHex: pinResult.contentHash,
    );

    await _repository.markPublished(version);

    return VaultPublishResult(
      cid: pinResult.cid,
      contentHash: pinResult.contentHash,
      providersOk: pinResult.providersOk,
      providersFailed: pinResult.providersFailed,
      transactionHash: txResult.transactionHash,
    );
  }
}

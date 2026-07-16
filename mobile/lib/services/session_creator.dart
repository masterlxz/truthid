import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import '../contracts/abis.dart';
import '../utils/user_operation.dart';
import 'blockchain_service.dart';
import 'device_key_service.dart';
import 'pimlico_bundler_client.dart';
import 'user_operation_signer.dart';

// Resultado de uma submissão bem-sucedida. `transactionHash` fica null se o
// bundler ainda não confirmou a UserOperation dentro do timeout de polling —
// a UserOp já foi aceita e vai ser minerada de qualquer forma, então isso não
// é um erro, só uma confirmação que não chegou a tempo.
class SessionCreationResult {
  final String userOpHash;
  final String? transactionHash;

  const SessionCreationResult({
    required this.userOpHash,
    this.transactionHash,
  });
}

({Uint8List r, Uint8List s, int v}) _splitSignature(String signatureHex) {
  final bytes = hexToBytes(signatureHex);
  assert(
    bytes.length == 65,
    'assinatura de sessão deveria ter 65 bytes (r||s||v), recebeu ${bytes.length}',
  );
  return (
    r: Uint8List.fromList(bytes.sublist(0, 32)),
    s: Uint8List.fromList(bytes.sublist(32, 64)),
    v: bytes[64],
  );
}

// Constrói, assina e envia UserOperations através da smart account do
// usuário: chamadas ao `SessionRegistry` (createSession na etapa 14.9.5,
// fecha o ciclo aberto na 14.9.1; revokeSession depois) e transferências
// nativas de ETH (withdraw, aba Wallet) — todas reaproveitando o mesmo
// núcleo `_executeViaUserOp`. O device, como signer tier "device", monta e
// envia a UserOp via bundler — a smart account paga o próprio gas, sem
// paymaster (decisão de design do projeto).
class SessionCreator {
  final BlockchainService _blockchainService;
  final PimlicoBundlerClient _bundlerClient;
  final DeviceKeyService _deviceKeyService;
  final EthereumAddress _entryPoint;
  final BigInt _chainId;
  final Duration _receiptPollInterval;
  final int _receiptPollMaxAttempts;

  static final _sessionRegistryContract = DeployedContract(
    ContractAbi.fromJson(sessionRegistryAbi, 'SessionRegistry'),
    EthereumAddress.fromHex(BlockchainService.sessionRegistryAddress),
  );

  static final _truthidAccountAbiParsed =
      ContractAbi.fromJson(truthidAccountAbi, 'TruthIDAccount');

  static final _vaultRegistryContract = DeployedContract(
    ContractAbi.fromJson(vaultRegistryAbi, 'VaultRegistry'),
    EthereumAddress.fromHex(BlockchainService.vaultRegistryAddress),
  );

  // Polling do recibo: 30 tentativas de 2s (~60s) por padrão — generoso o
  // bastante pra um bloco confirmar em L2 sem travar o app indefinidamente.
  // Configurável pra permitir testes rápidos (intervalo mínimo/poucas tentativas).
  SessionCreator({
    required PimlicoBundlerClient bundlerClient,
    BlockchainService? blockchainService,
    DeviceKeyService? deviceKeyService,
    EthereumAddress? entryPoint,
    BigInt? chainId,
    Duration receiptPollInterval = const Duration(seconds: 2),
    int receiptPollMaxAttempts = 30,
  })  : _bundlerClient = bundlerClient,
        _blockchainService = blockchainService ?? BlockchainService(),
        _deviceKeyService = deviceKeyService ?? DeviceKeyService(),
        _entryPoint = entryPoint ?? EthereumAddress.fromHex(entryPointV07Address),
        _chainId = chainId ?? BlockchainService.chainId,
        _receiptPollInterval = receiptPollInterval,
        _receiptPollMaxAttempts = receiptPollMaxAttempts;

  Future<SessionCreationResult> createSession({
    required BigInt identityId,
    required EthereumAddress smartAccountAddress,
    required Uint8List sessionHash,
    required EthereumAddress devicePubKey,
    required String sessionSignatureHex,
  }) async {
    final sig = _splitSignature(sessionSignatureHex);

    final createSessionCallData =
        _sessionRegistryContract.function('createSession').encodeCall([
      sessionHash,
      identityId,
      devicePubKey,
      sig.r,
      sig.s,
      BigInt.from(sig.v), // web3dart codifica todo "uintN" como BigInt, mesmo uint8
    ]);

    return _executeViaUserOp(
      smartAccountAddress: smartAccountAddress,
      dest: EthereumAddress.fromHex(BlockchainService.sessionRegistryAddress),
      value: BigInt.zero,
      innerCallData: createSessionCallData,
    );
  }

  // Revoga uma sessão existente através da própria smart account do usuário —
  // mesmo caminho da 14.9.5 (device tier assina a UserOp, smart account paga
  // o gas). `SessionRegistry.revokeSession` só exige que `msg.sender` seja o
  // controller da identidade (a smart account); como o device não é bloqueado
  // de chamar SessionRegistry (só DeviceRegistry tem essa restrição — ver
  // Problema 3 do design da Fase 14), revogar do mobile já era possível
  // desde a 14.9.5, só nunca tinha sido exposto na UI (o aviso "use o
  // desktop" em SessionsScreen ficou desatualizado depois dessa etapa).
  Future<SessionCreationResult> revokeSession({
    required EthereumAddress smartAccountAddress,
    required Uint8List sessionHash,
  }) async {
    final revokeCallData = _sessionRegistryContract
        .function('revokeSession')
        .encodeCall([sessionHash]);

    return _executeViaUserOp(
      smartAccountAddress: smartAccountAddress,
      dest: EthereumAddress.fromHex(BlockchainService.sessionRegistryAddress),
      value: BigInt.zero,
      innerCallData: revokeCallData,
    );
  }

  // Saca ETH nativo da smart account pro endereço `destination`, via UserOp
  // assinada pelo device — mesmo caminho de revokeSession/createSession.
  // Confirmado em TruthIDAccount._isDeviceCallAllowed (contracts/src/
  // TruthIDAccount.sol) que `value` não é restringido pro tier device: só o
  // `dest` precisa não ser a própria smart account nem um contrato bloqueado
  // (DeviceRegistry/IdentityRegistry/RecoveryManager). Por isso o mobile não
  // precisa do owner (Ledger) pra sacar, ao contrário do WithdrawModal do
  // Desktop (que assina uma tx direta com a Ledger).
  Future<SessionCreationResult> withdraw({
    required EthereumAddress smartAccountAddress,
    required EthereumAddress destination,
    required BigInt amountWei,
  }) {
    return _executeViaUserOp(
      smartAccountAddress: smartAccountAddress,
      dest: destination,
      value: amountWei,
      innerCallData: Uint8List(0),
    );
  }

  // Publica a referência do vault (CID + hash do conteúdo) via
  // VaultRegistry.updateVault — mesmo caminho de createSession/revokeSession
  // (device tier assina, smart account paga o gas). VaultRegistry não está
  // bloqueado pra devices em TruthIDAccount._isDeviceCallAllowed (só
  // DeviceRegistry/IdentityRegistry/RecoveryManager estão), e o próprio
  // Desktop já roteia updateVault do mesmo jeito (via TruthIDAccount.execute,
  // desktop/src/hooks/useVaultPublish.ts) — aqui só quem assina muda (device
  // key em vez da Ledger). Ver PROJECT_STATE.md, Sessão 97.
  Future<SessionCreationResult> updateVault({
    required EthereumAddress smartAccountAddress,
    required String cid,
    required String contentHashHex,
  }) {
    final contentHash = hexToBytes(contentHashHex);
    assert(
      contentHash.length == 32,
      'contentHash deveria ter 32 bytes, recebeu ${contentHash.length}',
    );

    final updateVaultCallData = _vaultRegistryContract
        .function('updateVault')
        .encodeCall([cid, Uint8List.fromList(contentHash)]);

    return _executeViaUserOp(
      smartAccountAddress: smartAccountAddress,
      dest: EthereumAddress.fromHex(BlockchainService.vaultRegistryAddress),
      value: BigInt.zero,
      innerCallData: updateVaultCallData,
    );
  }

  // Executa uma chamada arbitrária (dest/value/callData decididos por quem
  // chama, não pelo SessionCreator) via `execute` na smart account — usado
  // pelo canal cross-device de `/sign-request` (SignRequestApprovalScreen),
  // que recebe esses campos de um app terceiro depois de aprovação humana.
  // Repassa direto pro núcleo já existente, sem lógica nova.
  Future<SessionCreationResult> executeArbitraryCall({
    required EthereumAddress smartAccountAddress,
    required EthereumAddress dest,
    required BigInt value,
    required Uint8List innerCallData,
  }) {
    return _executeViaUserOp(
      smartAccountAddress: smartAccountAddress,
      dest: dest,
      value: value,
      innerCallData: innerCallData,
    );
  }

  // Monta, assina e envia a UserOp que chama `execute(dest, value, innerCallData)`
  // na smart account — núcleo compartilhado por createSession/revokeSession/withdraw.
  Future<SessionCreationResult> _executeViaUserOp({
    required EthereumAddress smartAccountAddress,
    required EthereumAddress dest,
    required BigInt value,
    required Uint8List innerCallData,
  }) async {
    // DeployedContract aqui só serve pra alcançar a função pelo ABI — o
    // endereço de destino real (`dest`) é passado explicitamente abaixo, já
    // que o `sender`/smart account varia por identidade.
    final truthidAccount = DeployedContract(
      _truthidAccountAbiParsed,
      smartAccountAddress,
    );
    final executeCallData = truthidAccount.function('execute').encodeCall([
      dest,
      value,
      innerCallData,
    ]);

    final nonce =
        await _blockchainService.getSmartAccountNonce(smartAccountAddress);
    final gasPrice = await _bundlerClient.getUserOperationGasPrice();

    var userOp = UserOperationV07(
      sender: smartAccountAddress,
      nonce: nonce,
      callData: executeCallData,
      callGasLimit: BigInt.zero,
      verificationGasLimit: BigInt.zero,
      preVerificationGas: BigInt.zero,
      maxFeePerGas: gasPrice.maxFeePerGas,
      maxPriorityFeePerGas: gasPrice.maxPriorityFeePerGas,
      signature: Uint8List(65), // placeholder — só a estimativa de gas usa isto
    );

    final estimate = await _bundlerClient.estimateUserOperationGas(userOp);
    userOp = userOp.copyWith(
      callGasLimit: estimate.callGasLimit,
      verificationGasLimit: estimate.verificationGasLimit,
      preVerificationGas: estimate.preVerificationGas,
    );

    final signedOp = await signUserOperation(
      userOperation: userOp,
      entryPoint: _entryPoint,
      chainId: _chainId,
      deviceKeyService: _deviceKeyService,
    );

    final userOpHash = await _bundlerClient.sendUserOperation(signedOp);
    final receipt = await _waitForReceipt(userOpHash);

    return SessionCreationResult(
      userOpHash: userOpHash,
      transactionHash: receipt?.transactionHash,
    );
  }

  Future<UserOperationReceipt?> _waitForReceipt(String userOpHash) async {
    for (var attempt = 0; attempt < _receiptPollMaxAttempts; attempt++) {
      final receipt = await _bundlerClient.getUserOperationReceipt(userOpHash);
      if (receipt != null) return receipt;
      await Future.delayed(_receiptPollInterval);
    }
    return null;
  }
}

import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

// Endereço padrão do EntryPoint v0.7 (eth-infinitism) — mesmo em todas as chains.
const entryPointV07Address = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';

// User Operation ERC-4337 v0.7, na forma "não empacotada" usada pelos
// métodos JSON-RPC do bundler (eth_sendUserOperation, eth_estimateUserOperationGas)
// — espelha o tipo `UserOperation` do viem para entryPointVersion "0.7"
// (etapa 14.9.3 consome esse formato pra falar com o bundler Pimlico).
class UserOperationV07 {
  final EthereumAddress sender;
  final BigInt nonce;
  final EthereumAddress? factory;
  final Uint8List factoryData;
  final Uint8List callData;
  final BigInt callGasLimit;
  final BigInt verificationGasLimit;
  final BigInt preVerificationGas;
  final BigInt maxFeePerGas;
  final BigInt maxPriorityFeePerGas;
  final EthereumAddress? paymaster;
  final BigInt paymasterVerificationGasLimit;
  final BigInt paymasterPostOpGasLimit;
  final Uint8List paymasterData;
  final Uint8List signature;

  UserOperationV07({
    required this.sender,
    required this.nonce,
    this.factory,
    Uint8List? factoryData,
    required this.callData,
    required this.callGasLimit,
    required this.verificationGasLimit,
    required this.preVerificationGas,
    required this.maxFeePerGas,
    required this.maxPriorityFeePerGas,
    this.paymaster,
    BigInt? paymasterVerificationGasLimit,
    BigInt? paymasterPostOpGasLimit,
    Uint8List? paymasterData,
    Uint8List? signature,
  })  : factoryData = factoryData ?? Uint8List(0),
        paymasterVerificationGasLimit =
            paymasterVerificationGasLimit ?? BigInt.zero,
        paymasterPostOpGasLimit = paymasterPostOpGasLimit ?? BigInt.zero,
        paymasterData = paymasterData ?? Uint8List(0),
        signature = signature ?? Uint8List(0);
}

// Forma "empacotada" da User Operation — a que o EntryPoint/TruthIDAccount
// realmente decodifica on-chain (struct PackedUserOperation do eth-infinitism).
// `accountGasLimits` e `gasFees` são cada um 32 bytes (dois uint128 concatenados).
class PackedUserOperation {
  final EthereumAddress sender;
  final BigInt nonce;
  final Uint8List initCode;
  final Uint8List callData;
  final Uint8List accountGasLimits;
  final BigInt preVerificationGas;
  final Uint8List gasFees;
  final Uint8List paymasterAndData;
  final Uint8List signature;

  const PackedUserOperation({
    required this.sender,
    required this.nonce,
    required this.initCode,
    required this.callData,
    required this.accountGasLimits,
    required this.preVerificationGas,
    required this.gasFees,
    required this.paymasterAndData,
    required this.signature,
  });
}

Uint8List _uintToBytes(BigInt value, int byteLength) {
  var v = value;
  final bytes = Uint8List(byteLength);
  final mask = BigInt.from(0xff);
  for (var i = byteLength - 1; i >= 0; i--) {
    bytes[i] = (v & mask).toInt();
    v = v >> 8;
  }
  return bytes;
}

Uint8List _addressWord(EthereumAddress address) {
  final word = Uint8List(32);
  word.setRange(12, 32, address.addressBytes);
  return word;
}

Uint8List _uintWord(BigInt value) => _uintToBytes(value, 32);

Uint8List _packUint128Pair(BigInt hi, BigInt lo) => Uint8List.fromList([
      ..._uintToBytes(hi, 16),
      ..._uintToBytes(lo, 16),
    ]);

Uint8List _buildInitCode(UserOperationV07 op) {
  if (op.factory == null) return Uint8List(0);
  return Uint8List.fromList([...op.factory!.addressBytes, ...op.factoryData]);
}

Uint8List _buildPaymasterAndData(UserOperationV07 op) {
  if (op.paymaster == null) return Uint8List(0);
  return Uint8List.fromList([
    ...op.paymaster!.addressBytes,
    ..._uintToBytes(op.paymasterVerificationGasLimit, 16),
    ..._uintToBytes(op.paymasterPostOpGasLimit, 16),
    ...op.paymasterData,
  ]);
}

PackedUserOperation toPackedUserOperation(UserOperationV07 op) {
  return PackedUserOperation(
    sender: op.sender,
    nonce: op.nonce,
    initCode: _buildInitCode(op),
    callData: op.callData,
    accountGasLimits:
        _packUint128Pair(op.verificationGasLimit, op.callGasLimit),
    preVerificationGas: op.preVerificationGas,
    gasFees: _packUint128Pair(op.maxPriorityFeePerGas, op.maxFeePerGas),
    paymasterAndData: _buildPaymasterAndData(op),
    signature: op.signature,
  );
}

// Espelha bit a bit `EntryPoint.getUserOpHash` / `UserOperationLib.hash` (v0.7):
//
//   innerHash = keccak256(abi.encode(
//     sender, nonce, keccak256(initCode), keccak256(callData),
//     accountGasLimits, preVerificationGas, gasFees, keccak256(paymasterAndData)
//   ))
//   userOpHash = keccak256(abi.encode(innerHash, entryPoint, chainId))
//
// Todos os campos do abi.encode acima são de tamanho estático (address,
// uint256, bytes32), então a codificação é só a concatenação de palavras de
// 32 bytes, sem cabeçalhos de offset — dispensa um encoder ABI genérico.
Uint8List computeUserOperationHash({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPoint,
  required BigInt chainId,
}) {
  final packed = toPackedUserOperation(userOperation);

  final innerEncoded = Uint8List.fromList([
    ..._addressWord(packed.sender),
    ..._uintWord(packed.nonce),
    ...keccak256(packed.initCode),
    ...keccak256(packed.callData),
    ...packed.accountGasLimits,
    ..._uintWord(packed.preVerificationGas),
    ...packed.gasFees,
    ...keccak256(packed.paymasterAndData),
  ]);
  final innerHash = keccak256(innerEncoded);

  final outerEncoded = Uint8List.fromList([
    ...innerHash,
    ..._addressWord(entryPoint),
    ..._uintWord(chainId),
  ]);
  return keccak256(outerEncoded);
}

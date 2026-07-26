import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'user_operation.dart' show addressWord, uint256Word;

// Espelha bit a bit o hash que `SessionRegistry.createSession` passou a
// exigir a partir do fix C4 (replay cross-chain, ver contracts/src/SessionRegistry.sol):
//
//   domainHash = keccak256(abi.encode(block.chainid, address(this), hash))
//
// `chainId`/`sessionRegistryAddress`/`hash` são todos de tamanho estático
// (uint256/address/bytes32), então a codificação é só a concatenação das
// 3 palavras de 32 bytes — mesma técnica já usada por `computeUserOperationHash`
// em user_operation.dart, sem precisar de encoder ABI genérico.
Uint8List buildSessionDomainHash({
  required BigInt chainId,
  required EthereumAddress sessionRegistryAddress,
  required Uint8List sessionHash,
}) {
  final encoded = Uint8List.fromList([
    ...uint256Word(chainId),
    ...addressWord(sessionRegistryAddress),
    ...sessionHash,
  ]);
  return keccak256(encoded);
}

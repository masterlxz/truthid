import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'contracts.dart';
import 'truthid_account_bytecode.dart';
import 'types.dart';

/// Left-pads a 20-byte address to a 32-byte ABI word (`abi.encode`, not packed).
Uint8List _encodeAddressPadded(String addressHex) {
  final bytes = hexToBytes(addressHex);
  final word = Uint8List(32);
  word.setRange(12, 32, bytes);
  return word;
}

Uint8List _uint256Bytes(BigInt value) {
  final bytes = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    bytes[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return bytes;
}

/// Predicts a TruthIDAccount's address via CREATE2 before it's deployed —
/// pure local computation, no RPC call needed. Same algorithm as
/// desktop/src/utils/computeSmartAccountAddress.ts and the TypeScript/
/// Python/Ruby SDKs' computeSmartAccountAddress/compute_smart_account_address.
String computeSmartAccountAddress(
  String ledgerAddress,
  Network network, {
  BigInt? index,
}) {
  final idx = index ?? BigInt.zero;
  final factoryAddress = smartAccountFactoryAddresses[network]!;

  // Must be packed (address, 20 bytes, no left-pad, then uint256, 32 bytes),
  // not abi.encode — the contract uses abi.encodePacked(owner_, index).
  // Using the wrong encoding here produces a different salt than the
  // factory computes on-chain, yielding a controller address that never
  // matches reality (this exact mistake caused a real bug once, see
  // desktop/src/utils/computeSmartAccountAddress.ts's own comment).
  final ledgerBytes = hexToBytes(ledgerAddress);
  final saltInput = Uint8List.fromList([
    ...ledgerBytes,
    ..._uint256Bytes(idx),
  ]);
  final salt = keccak256(saltInput);

  final constructorArgs = Uint8List.fromList([
    ..._encodeAddressPadded(entryPointV07Address),
    ..._encodeAddressPadded(deviceRegistryAddresses[network]!),
    ..._encodeAddressPadded(identityRegistryAddresses[network]!),
    ..._encodeAddressPadded(recoveryManagerAddresses[network]!),
    ..._encodeAddressPadded(ledgerAddress),
  ]);

  final creationCodeBytes = hexToBytes(truthIDAccountCreationCode);
  final initCode = Uint8List.fromList([...creationCodeBytes, ...constructorArgs]);
  final initCodeHash = keccak256(initCode);

  final factoryBytes = hexToBytes(factoryAddress);
  final create2Input = Uint8List.fromList([0xff, ...factoryBytes, ...salt, ...initCodeHash]);
  final addressHash = keccak256(create2Input);

  final addressBytes = addressHash.sublist(12);
  return EthereumAddress(addressBytes).hexEip55;
}

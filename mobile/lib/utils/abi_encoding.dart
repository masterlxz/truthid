import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

/// Codificação ABI "à mão" de `uint256`/`address` em slots de 32 bytes —
/// usada nos lugares que evitam `ContractFunction.encodeCall`/`decode`
/// (bug real e documentado do `web3dart` com um campo dinâmico, tipo
/// `string`, no meio de campos estáticos — ver comentário em
/// `BlockchainService.getIdentityByUsername`). Compartilhado entre
/// `BlockchainService` e `identity_consent_hash.dart`, que antes tinham cada
/// um sua própria cópia idêntica (achado de duplicação, P82 #5).
Uint8List uint256Bytes(BigInt value) {
  final hex = value.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(List.generate(
      32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
}

/// Endereço (20 bytes) alinhado à direita num slot de 32 bytes — mesma
/// convenção ABI de [uint256Bytes], só com zeros à esquerda em vez de um
/// valor numérico.
Uint8List addressBytes(EthereumAddress address) {
  final raw = address.addressBytes;
  return Uint8List.fromList([...Uint8List(32 - raw.length), ...raw]);
}

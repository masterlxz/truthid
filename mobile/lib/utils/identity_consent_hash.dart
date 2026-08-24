import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

/// Reproduz `desktop/src/utils/buildIdentityConsentHash.ts` byte a byte:
/// `keccak256(abi.encode(chainId, identityRegistryAddress, username, controller))`.
/// É o hash que a wallet assina (`personal_sign`) como consentimento pra
/// `IdentityRegistry.createIdentity` — `IdentityRegistry.sol` recomputa o
/// mesmo hash e recupera o signer via `ecrecover`.
///
/// Codificação feita à mão, sem `ContractFunction.encodeCall` — mesma técnica
/// já usada em `BlockchainService.getIdentityByUsername` pra evitar um bug
/// real e documentado do `web3dart` (Sessão 70): a construção/decodificação
/// via `ContractFunction` não lida direito com uma lista de campos que tem um
/// tipo dinâmico (`string`) no meio de campos estáticos — exatamente a forma
/// desta assinatura (`uint256, address, string, address`). Codificar à mão
/// evita qualquer contato com esse caminho.
Uint8List buildIdentityConsentHash({
  required BigInt chainId,
  required EthereumAddress identityRegistryAddress,
  required String username,
  required EthereumAddress controller,
}) {
  final usernameBytes = Uint8List.fromList(utf8.encode(username));
  final paddedUsernameLen = ((usernameBytes.length + 31) ~/ 32) * 32;

  // 4 slots de "head" (32 bytes cada) antes dos dados dinâmicos da string —
  // o offset do parâmetro dinâmico (username) é sempre 4*32 = 128 aqui,
  // porque username é o único campo dinâmico entre os 4 argumentos.
  final encoded = BytesBuilder()
    ..add(_uint256Bytes(chainId))
    ..add(_addressBytes(identityRegistryAddress))
    ..add(_uint256Bytes(BigInt.from(128)))
    ..add(_addressBytes(controller))
    ..add(_uint256Bytes(BigInt.from(usernameBytes.length)))
    ..add(usernameBytes)
    ..add(Uint8List(paddedUsernameLen - usernameBytes.length));

  return keccak256(encoded.toBytes());
}

Uint8List _uint256Bytes(BigInt value) {
  final hex = value.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(List.generate(
      32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
}

// Endereço (20 bytes) alinhado à direita num slot de 32 bytes — mesma
// convenção ABI usada por _uint256Bytes acima, só com zeros à esquerda em
// vez de um valor numérico.
Uint8List _addressBytes(EthereumAddress address) {
  final raw = address.addressBytes;
  return Uint8List.fromList([...Uint8List(32 - raw.length), ...raw]);
}

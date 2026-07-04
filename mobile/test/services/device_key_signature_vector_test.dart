import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

// Prova que `EthPrivateKey.signPersonalMessageToUint8List` -- a primitiva
// que `DeviceKeyService.signHash` usa por baixo -- produz byte a byte a
// mesma assinatura que `viem/accounts` `signMessage({ message: { raw } })`
// para o mesmo par (chave, hash). Não importa `DeviceKeyService` de
// propósito: a chave dele não é injetável (gerada/lida do secure storage
// internamente), então a prova de correção criptográfica passa direto pela
// API pública do web3dart, isolada da camada de storage.
//
// Chave usada: conta #0 padrão do Anvil/Hardhat -- pública, sem fundos
// reais, usada só como vetor de teste determinístico.
//
// Vetor gerado com `viem` v2.52.2 (Node, dentro de `desktop/`):
//   privateKeyToAccount('0xac09...ff80').address
//     -> 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
//   keccak256(toBytes('truthid-14.9.4-known-signature-vector'))
//     -> 0x4c0edff4da8c663198f35c78ab485687133310c50c343920b0e24510b2581b37
//   signMessage({ privateKey, message: { raw: hash } })
//     -> 0xc957aeb33d6e8289d733442cf9b44fbafc6c1c07fbb71eef974c724cc087dea
//        e0a4be53c6a97b8f41e53559d6327017adcf62341fc176583751ab61f1020f85
//        51c
void main() {
  test(
      'EthPrivateKey.signPersonalMessageToUint8List bate byte a byte com o '
      'vetor conhecido (viem signMessage)', () {
    const knownPrivateKeyHex =
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
    const knownAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    const expectedSignatureHex =
        '0xc957aeb33d6e8289d733442cf9b44fbafc6c1c07fbb71eef974c724cc087dea'
        'e0a4be53c6a97b8f41e53559d6327017adcf62341fc176583751ab61f1020f85'
        '51c';

    final key = EthPrivateKey.fromHex(knownPrivateKeyHex);
    expect(key.address.hexEip55, knownAddress);

    final hash = keccak256(
      Uint8List.fromList(
        utf8.encode('truthid-14.9.4-known-signature-vector'),
      ),
    );

    final signature = key.signPersonalMessageToUint8List(hash);

    expect(signature.length, 65);
    expect(bytesToHex(signature, include0x: true), expectedSignatureHex);
  });
}

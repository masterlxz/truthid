import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/contracts/abis.dart';

// blockchain_service.dart faz `_contract.function('nomeDaFuncao')` pra cada
// chamada on-chain — se o nome não existir no ABI (json), o lookup lança
// `Bad state: No element`, sem chegar nem a fazer a chamada de rede. Como os
// testes de blockchain_service.dart mockam o serviço inteiro, esse lookup
// nunca era exercitado de verdade — foi assim que `deviceVaultKeys` ficou
// faltando no ABI por várias sessões sem nenhum teste pegar (achado
// investigando por que `tryRecoverFromChain` sempre retornava `false` mesmo
// com a vault key já on-chain). Este teste garante que toda função realmente
// chamada em blockchain_service.dart existe no ABI correspondente.
final _dummyAddress = EthereumAddress.fromHex(
  '0x0000000000000000000000000000000000000001',
);

void main() {
  test('deviceRegistryAbi tem todas as funções usadas em blockchain_service.dart', () {
    final contract = DeployedContract(
      ContractAbi.fromJson(deviceRegistryAbi, 'DeviceRegistry'),
      _dummyAddress,
    );

    expect(() => contract.function('getDevice'), returnsNormally);
    expect(() => contract.function('deviceVaultKeys'), returnsNormally);
  });

  test('sessionRegistryAbi tem todas as funções usadas em blockchain_service.dart', () {
    final contract = DeployedContract(
      ContractAbi.fromJson(sessionRegistryAbi, 'SessionRegistry'),
      _dummyAddress,
    );

    expect(() => contract.function('getSessionsByIdentity'), returnsNormally);
    expect(() => contract.function('getSession'), returnsNormally);
    expect(() => contract.function('isSessionRevoked'), returnsNormally);
  });

  test('entryPointAbi tem todas as funções usadas em blockchain_service.dart', () {
    final contract = DeployedContract(
      ContractAbi.fromJson(entryPointAbi, 'EntryPoint'),
      _dummyAddress,
    );

    expect(() => contract.function('getNonce'), returnsNormally);
  });
}

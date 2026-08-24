import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/blockchain_service.dart';

// Vetores gerados com `viem` (encodeFunctionData), mesmo pacote já usado no
// lado desktop — garante que o calldata codificado à mão em
// BlockchainService.buildCreateIdentityCalldata/buildCreateAccountCalldata
// (P68, fatia 1) bate byte a byte com o que os contratos reais esperam.
void main() {
  final blockchain = BlockchainService();

  group('buildCreateIdentityCalldata', () {
    test('bate com o vetor gerado via viem', () {
      final r = Uint8List.fromList(List.generate(32, (i) => i));
      final s = Uint8List.fromList(List.generate(32, (i) => i + 32));

      final calldata = blockchain.buildCreateIdentityCalldata(
        username: 'alice',
        controller: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
        v: 27,
        r: r,
        s: s,
      );

      expect(
        bytesToHex(calldata, include0x: true),
        '0x1b57893500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000001234567890123456789012345678901234567890000000000000000000000000000000000000000000000000000000000000001b000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f0000000000000000000000000000000000000000000000000000000000000005616c696365000000000000000000000000000000000000000000000000000000',
      );
    });
  });

  group('buildCreateAccountCalldata', () {
    test('bate com o vetor gerado via viem', () {
      final calldata = blockchain.buildCreateAccountCalldata(
        EthereumAddress.fromHex('0x1234567890123456789012345678901234567890'),
      );

      expect(
        bytesToHex(calldata, include0x: true),
        '0x5fbfb9cf00000000000000000000000012345678901234567890123456789012345678900000000000000000000000000000000000000000000000000000000000000000',
      );
    });
  });
}

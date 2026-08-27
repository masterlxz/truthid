import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/utils/abi_encoding.dart';

// Extraído de BlockchainService/identity_consent_hash.dart (achado de
// duplicação, P82 #5) — cobertura direta da própria função compartilhada,
// além da cobertura indireta já existente via os vetores de
// identity_consent_hash_test.dart.
void main() {
  group('uint256Bytes', () {
    test('sempre devolve 32 bytes', () {
      expect(uint256Bytes(BigInt.zero).length, 32);
      expect(uint256Bytes(BigInt.from(128)).length, 32);
    });

    test('zero é 32 bytes zerados', () {
      expect(bytesToHex(uint256Bytes(BigInt.zero)), '0' * 64);
    });

    test('valor pequeno fica alinhado à direita (big-endian)', () {
      expect(bytesToHex(uint256Bytes(BigInt.from(128))),
          '${'0' * 62}80');
    });
  });

  group('addressBytes', () {
    test('sempre devolve 32 bytes', () {
      expect(
          addressBytes(EthereumAddress.fromHex(
                  '0x1234567890123456789012345678901234567890'))
              .length,
          32);
    });

    test('endereço fica alinhado à direita, com 12 bytes de zero à esquerda',
        () {
      final address = EthereumAddress.fromHex(
          '0x1234567890123456789012345678901234567890');
      expect(
        bytesToHex(addressBytes(address)),
        '${'0' * 24}1234567890123456789012345678901234567890',
      );
    });

    test('endereço zero é 32 bytes zerados', () {
      expect(
        bytesToHex(addressBytes(EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000000'))),
        '0' * 64,
      );
    });
  });
}

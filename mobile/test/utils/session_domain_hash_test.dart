import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/utils/session_domain_hash.dart';

// Vetores gerados com `viem` (encodeAbiParameters + keccak256), mesmo pacote
// já usado no lado desktop — pra garantir que a implementação Dart bate byte
// a byte com keccak256(abi.encode(chainId, address(this), hash)), a fórmula
// que contracts/src/SessionRegistry.sol:116-118 usa (fix C4, P26).
Uint8List _bytes(String hex) => hexToBytes(hex);

void main() {
  group('buildSessionDomainHash — vetores conhecidos (viem)', () {
    test('all_zero', () {
      final hash = buildSessionDomainHash(
        chainId: BigInt.zero,
        sessionRegistryAddress: EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000000'),
        sessionHash: Uint8List(32),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x46700b4d40ac5c35af2c22dda2787a91eb567b06c924a8fb8ae9a05b20c08c21',
      );
    });

    test('mainnet_session_registry', () {
      final hash = buildSessionDomainHash(
        chainId: BigInt.from(8453),
        sessionRegistryAddress: EthereumAddress.fromHex(
            '0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df'),
        sessionHash: _bytes('0x${'ab' * 32}'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x0244e97b45b592c3794f8162777217d269b585b3a3eef62528e1f2d8afafbe9e',
      );
    });

    test('sepolia_same_hash — chainId diferente muda o resultado (proteção C4)',
        () {
      final hash = buildSessionDomainHash(
        chainId: BigInt.from(84532),
        sessionRegistryAddress: EthereumAddress.fromHex(
            '0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df'),
        sessionHash: _bytes('0x${'ab' * 32}'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0xc5e2e4d87473325bc9e262f0276703a0298e18fd28b329c939a003515b919fc4',
      );
    });
  });

  group('buildSessionDomainHash — propriedades', () {
    final baseAddress = EthereumAddress.fromHex(
        '0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df');
    final baseHash = _bytes('0x${'11' * 32}');

    Uint8List build({
      BigInt? chainId,
      EthereumAddress? sessionRegistryAddress,
      Uint8List? sessionHash,
    }) =>
        buildSessionDomainHash(
          chainId: chainId ?? BigInt.from(8453),
          sessionRegistryAddress: sessionRegistryAddress ?? baseAddress,
          sessionHash: sessionHash ?? baseHash,
        );

    test('é determinístico — mesmas entradas produzem o mesmo hash', () {
      expect(bytesToHex(build()), bytesToHex(build()));
    });

    test('mudar o chainId muda o hash', () {
      expect(
        bytesToHex(build(chainId: BigInt.from(8453))),
        isNot(bytesToHex(build(chainId: BigInt.from(84532)))),
      );
    });

    test('mudar o endereço do SessionRegistry muda o hash', () {
      final otherAddress = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111');
      expect(
        bytesToHex(build()),
        isNot(bytesToHex(build(sessionRegistryAddress: otherAddress))),
      );
    });

    test('mudar o sessionHash muda o hash', () {
      final otherHash = _bytes('0x${'22' * 32}');
      expect(
        bytesToHex(build()),
        isNot(bytesToHex(build(sessionHash: otherHash))),
      );
    });

    test('sempre devolve 32 bytes', () {
      expect(build().length, 32);
    });
  });
}

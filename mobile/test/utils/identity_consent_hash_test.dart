import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/utils/identity_consent_hash.dart';

// Vetores gerados com `viem` (encodeAbiParameters + keccak256), mesmo pacote
// já usado no lado desktop (`buildIdentityConsentHash.ts`) — garante que a
// implementação Dart bate byte a byte com
// keccak256(abi.encode(chainId, address(this), username, controller)), a
// fórmula que `IdentityRegistry.sol` usa pra verificar o consentimento
// (débito #17).
void main() {
  group('buildIdentityConsentHash — vetores conhecidos (viem)', () {
    test('zero_ish — username vazio', () {
      final hash = buildIdentityConsentHash(
        chainId: BigInt.zero,
        identityRegistryAddress: EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000000'),
        username: '',
        controller: EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000000'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x8189ed11859eb4be26e83fc724cf6ba27e2bbe87da9e4f9c587de8dd21c2d335',
      );
    });

    test('mainnet_alice — chain/registry reais, username curto', () {
      final hash = buildIdentityConsentHash(
        chainId: BigInt.from(8453),
        identityRegistryAddress: EthereumAddress.fromHex(
            '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962'),
        username: 'alice',
        controller: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x7dd1a71fd536c954b16a4d4526e6014fdff1ccc95763e903116587f1893f6c44',
      );
    });

    test('mainnet_32char — username com exatamente 32 bytes (sem padding)',
        () {
      final hash = buildIdentityConsentHash(
        chainId: BigInt.from(8453),
        identityRegistryAddress: EthereumAddress.fromHex(
            '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962'),
        username: 'abcdefghijklmnopqrstuvwxyz123456',
        controller: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0xf3f47255d2af7c3c9ebd5a90ff05dbe42349e1949053aa82a48fb8fcf65a34e4',
      );
    });

    test('sepolia_alice — chainId diferente muda o resultado', () {
      final hash = buildIdentityConsentHash(
        chainId: BigInt.from(84532),
        identityRegistryAddress: EthereumAddress.fromHex(
            '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962'),
        username: 'alice',
        controller: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x54d08b0e2931ceb6e81838941a7900b9d74293b9aa152b7472c16dfa91ec5096',
      );
    });
  });

  group('buildIdentityConsentHash — propriedades', () {
    final baseRegistry = EthereumAddress.fromHex(
        '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962');
    final baseController = EthereumAddress.fromHex(
        '0x1234567890123456789012345678901234567890');

    Uint8List build({
      BigInt? chainId,
      EthereumAddress? identityRegistryAddress,
      String? username,
      EthereumAddress? controller,
    }) =>
        buildIdentityConsentHash(
          chainId: chainId ?? BigInt.from(8453),
          identityRegistryAddress:
              identityRegistryAddress ?? baseRegistry,
          username: username ?? 'alice',
          controller: controller ?? baseController,
        );

    test('é determinístico — mesmas entradas produzem o mesmo hash', () {
      expect(bytesToHex(build()), bytesToHex(build()));
    });

    test('mudar o username muda o hash', () {
      expect(
        bytesToHex(build(username: 'alice')),
        isNot(bytesToHex(build(username: 'bob'))),
      );
    });

    test('mudar o controller muda o hash', () {
      final other = EthereumAddress.fromHex(
          '0x1111111111111111111111111111111111111111');
      expect(
        bytesToHex(build()),
        isNot(bytesToHex(build(controller: other))),
      );
    });

    test('sempre devolve 32 bytes', () {
      expect(build().length, 32);
    });
  });
}

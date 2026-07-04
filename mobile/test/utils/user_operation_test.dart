import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/utils/user_operation.dart';

// Vetores gerados com `viem/account-abstraction` (getUserOperationHash,
// entryPointVersion "0.7") — mesmo pacote já usado no lado desktop (viem) —
// pra garantir que a implementação Dart bate byte a byte com a fórmula que o
// EntryPoint on-chain usa. Ver Sessão de Fase 14.9.2 no PROJECT_STATE.md pro
// script usado pra gerar estes hashes.
const _entryPoint = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';

Uint8List _bytes(String hex) => hexToBytes(hex);

void main() {
  group('computeUserOperationHash — vetores conhecidos (viem v2.52.2)', () {
    test('all_zero', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x0000000000000000000000000000000000000000'),
        nonce: BigInt.zero,
        callData: Uint8List(0),
        callGasLimit: BigInt.zero,
        verificationGasLimit: BigInt.zero,
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
      );

      final hash = computeUserOperationHash(
        userOperation: op,
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: BigInt.from(8453),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0xa7b74a3887217c32acb631306574bac263415b77bf91d0e1b9cfda7978dc3c7b',
      );
    });

    test('no_factory_no_paymaster', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
        nonce: BigInt.from(7),
        callData: _bytes('0xabcdef01'),
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
      );

      final hash = computeUserOperationHash(
        userOperation: op,
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: BigInt.from(8453),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0xae94190d47190ec9ce40f9a5e0f3aa9397208df172050e749446ced9072ba28b',
      );
    });

    test('with_factory', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0xabCabCabcabcaBCAbCABCaBCabCabcabcabCabcA'),
        nonce: BigInt.from(5),
        factory: EthereumAddress.fromHex(
            '0x1111111111111111111111111111111111111111'),
        factoryData: _bytes('0xdeadbeef'),
        callData: _bytes('0x1234'),
        callGasLimit: BigInt.from(300000),
        verificationGasLimit: BigInt.from(400000),
        preVerificationGas: BigInt.from(60000),
        maxFeePerGas: BigInt.from(2000000000),
        maxPriorityFeePerGas: BigInt.from(150000000),
      );

      final hash = computeUserOperationHash(
        userOperation: op,
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: BigInt.from(84532),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x6235da4b7e8f45cfcaa3e9c4873d8405bc576cfbdddc9492f7879200831e1c35',
      );
    });

    test('with_paymaster', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x9999999999999999999999999999999999999999'),
        nonce: BigInt.from(42),
        callData: _bytes('0xcafebabe'),
        callGasLimit: BigInt.from(150000),
        verificationGasLimit: BigInt.from(250000),
        preVerificationGas: BigInt.from(55000),
        maxFeePerGas: BigInt.from(3000000000),
        maxPriorityFeePerGas: BigInt.from(200000000),
        paymaster: EthereumAddress.fromHex(
            '0x2222222222222222222222222222222222222222'),
        paymasterVerificationGasLimit: BigInt.from(80000),
        paymasterPostOpGasLimit: BigInt.from(20000),
        paymasterData: _bytes('0xfeedface'),
      );

      final hash = computeUserOperationHash(
        userOperation: op,
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: BigInt.from(8453),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x7bb0f3ed93d36190d8f134881b75b76e950f5b5aa1844bb5a65ece20e4f18b6f',
      );
    });

    test('large_values_with_signature', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x362dC9570CC35C7Fa04635167a891Df02445B7DB'),
        nonce: BigInt.parse('340282366920938463463374607431768211455'),
        callData: _bytes(
            '0x1b11092d0000000000000000000000000000000000000000000000000000000000000001'),
        callGasLimit: BigInt.from(999999),
        verificationGasLimit: BigInt.from(888888),
        preVerificationGas: BigInt.from(77777),
        maxFeePerGas: BigInt.from(123456789),
        maxPriorityFeePerGas: BigInt.from(987654321),
        signature: _bytes('0xaabbccddeeff'),
      );

      final hash = computeUserOperationHash(
        userOperation: op,
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: BigInt.from(84532),
      );

      expect(
        bytesToHex(hash, include0x: true),
        '0x0b705240177f10e7715c7f8234b5b0538f03dd55cea312f1f0d7b28fd1f8cc8e',
      );
    });
  });

  group('toPackedUserOperation', () {
    test('empacota accountGasLimits e gasFees em 32 bytes cada', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
        nonce: BigInt.zero,
        callData: Uint8List(0),
        callGasLimit: BigInt.from(0x1234),
        verificationGasLimit: BigInt.from(0x5678),
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.from(0xabcd),
        maxPriorityFeePerGas: BigInt.from(0x9),
      );

      final packed = toPackedUserOperation(op);

      expect(packed.accountGasLimits.length, 32);
      expect(packed.gasFees.length, 32);
      // accountGasLimits = pad(verificationGasLimit, 16) ++ pad(callGasLimit, 16)
      expect(
        bytesToHex(packed.accountGasLimits, include0x: true),
        '0x${'5678'.padLeft(32, '0')}${'1234'.padLeft(32, '0')}',
      );
      // gasFees = pad(maxPriorityFeePerGas, 16) ++ pad(maxFeePerGas, 16)
      expect(
        bytesToHex(packed.gasFees, include0x: true),
        '0x${'9'.padLeft(32, '0')}${'abcd'.padLeft(32, '0')}',
      );
    });

    test('sem factory gera initCode vazio; sem paymaster gera paymasterAndData vazio',
        () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
        nonce: BigInt.zero,
        callData: Uint8List(0),
        callGasLimit: BigInt.zero,
        verificationGasLimit: BigInt.zero,
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
      );

      final packed = toPackedUserOperation(op);

      expect(packed.initCode, isEmpty);
      expect(packed.paymasterAndData, isEmpty);
    });

    test('com factory, initCode é factory ++ factoryData', () {
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0x1234567890123456789012345678901234567890'),
        nonce: BigInt.zero,
        factory: EthereumAddress.fromHex(
            '0x1111111111111111111111111111111111111111'),
        factoryData: _bytes('0xdeadbeef'),
        callData: Uint8List(0),
        callGasLimit: BigInt.zero,
        verificationGasLimit: BigInt.zero,
        preVerificationGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
      );

      final packed = toPackedUserOperation(op);

      expect(
        bytesToHex(packed.initCode, include0x: true),
        '0x1111111111111111111111111111111111111111deadbeef',
      );
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/pimlico_bundler_client.dart';
import 'package:truthid_mobile/utils/user_operation.dart';

class MockJsonRpcTransport extends Mock implements JsonRpcTransport {}

Uint8List _bytes(String hex) => hexToBytes(hex);

void main() {
  late MockJsonRpcTransport mockTransport;
  late PimlicoBundlerClient client;
  final bundlerUrl = Uri.parse('https://api.pimlico.io/v2/base/rpc?apikey=test');

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(<dynamic>[]);
  });

  setUp(() {
    mockTransport = MockJsonRpcTransport();
    client = PimlicoBundlerClient(
      bundlerUrl: bundlerUrl,
      transport: mockTransport,
    );
  });

  group('pimlicoBundlerUrl', () {
    test('monta a URL a partir da apiKey e da rede', () {
      final url = pimlicoBundlerUrl(apiKey: 'abc123', network: 'base-sepolia');
      expect(
        url.toString(),
        'https://api.pimlico.io/v2/base-sepolia/rpc?apikey=abc123',
      );
    });
  });

  group('serialização da UserOperation', () {
    test('sem factory e sem paymaster — chaves opcionais ausentes', () async {
      final sender =
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890');
      final op = UserOperationV07(
        sender: sender,
        nonce: BigInt.from(7),
        callData: _bytes('0xabcdef01'),
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
        maxFeePerGas: BigInt.from(1000000000),
        maxPriorityFeePerGas: BigInt.from(100000000),
      );

      when(() => mockTransport.call(any(), any(), any()))
          .thenAnswer((_) async => '0xuserOpHash');

      await client.sendUserOperation(op);

      final captured = verify(() => mockTransport.call(
            captureAny(),
            captureAny(),
            captureAny(),
          )).captured;
      expect(captured[1], 'eth_sendUserOperation');
      final params = captured[2] as List<dynamic>;
      final rpcOp = params[0] as Map<String, dynamic>;

      expect(rpcOp['sender'], sender.hexEip55);
      expect(rpcOp['nonce'], '0x7');
      expect(rpcOp['callData'], '0xabcdef01');
      expect(rpcOp['callGasLimit'], '0x186a0');
      expect(rpcOp['verificationGasLimit'], '0x30d40');
      expect(rpcOp['preVerificationGas'], '0xc350');
      expect(rpcOp['maxFeePerGas'], '0x3b9aca00');
      expect(rpcOp['maxPriorityFeePerGas'], '0x5f5e100');
      expect(rpcOp['signature'], '0x');
      expect(rpcOp.containsKey('factory'), isFalse);
      expect(rpcOp.containsKey('factoryData'), isFalse);
      expect(rpcOp.containsKey('paymaster'), isFalse);
      expect(rpcOp.containsKey('paymasterVerificationGasLimit'), isFalse);
      expect(rpcOp.containsKey('paymasterPostOpGasLimit'), isFalse);
      expect(rpcOp.containsKey('paymasterData'), isFalse);
      expect(params[1], client.entryPoint.hexEip55);
    });

    test('com factory — factory e factoryData presentes', () async {
      final factory =
          EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
      final op = UserOperationV07(
        sender: EthereumAddress.fromHex(
            '0xabCabCabcabcaBCAbCABCaBCabCabcabcabCabcA'),
        nonce: BigInt.from(5),
        factory: factory,
        factoryData: _bytes('0xdeadbeef'),
        callData: _bytes('0x1234'),
        callGasLimit: BigInt.from(300000),
        verificationGasLimit: BigInt.from(400000),
        preVerificationGas: BigInt.from(60000),
        maxFeePerGas: BigInt.from(2000000000),
        maxPriorityFeePerGas: BigInt.from(150000000),
      );

      when(() => mockTransport.call(any(), any(), any()))
          .thenAnswer((_) async => '0xuserOpHash');

      await client.sendUserOperation(op);

      final captured = verify(() => mockTransport.call(
            captureAny(),
            captureAny(),
            captureAny(),
          )).captured;
      final rpcOp =
          (captured[2] as List<dynamic>)[0] as Map<String, dynamic>;

      expect(rpcOp['factory'], factory.hexEip55);
      expect(rpcOp['factoryData'], '0xdeadbeef');
      expect(rpcOp.containsKey('paymaster'), isFalse);
    });

    test('com paymaster — os 4 campos de paymaster presentes juntos',
        () async {
      final paymaster =
          EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');
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
        paymaster: paymaster,
        paymasterVerificationGasLimit: BigInt.from(80000),
        paymasterPostOpGasLimit: BigInt.from(20000),
        paymasterData: _bytes('0xfeedface'),
      );

      when(() => mockTransport.call(any(), any(), any()))
          .thenAnswer((_) async => '0xuserOpHash');

      await client.sendUserOperation(op);

      final captured = verify(() => mockTransport.call(
            captureAny(),
            captureAny(),
            captureAny(),
          )).captured;
      final rpcOp =
          (captured[2] as List<dynamic>)[0] as Map<String, dynamic>;

      expect(rpcOp['paymaster'], paymaster.hexEip55);
      expect(rpcOp['paymasterVerificationGasLimit'], '0x13880');
      expect(rpcOp['paymasterPostOpGasLimit'], '0x4e20');
      expect(rpcOp['paymasterData'], '0xfeedface');
      expect(rpcOp.containsKey('factory'), isFalse);
    });
  });

  UserOperationV07 sampleOp() => UserOperationV07(
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

  group('estimateUserOperationGas', () {
    test('parseia a resposta sem campos opcionais de paymaster', () async {
      when(() => mockTransport.call(any(), 'eth_estimateUserOperationGas', any()))
          .thenAnswer((_) async => {
                'callGasLimit': '0x186a0',
                'verificationGasLimit': '0x30d40',
                'preVerificationGas': '0xc350',
              });

      final estimate = await client.estimateUserOperationGas(sampleOp());

      expect(estimate.callGasLimit, BigInt.from(100000));
      expect(estimate.verificationGasLimit, BigInt.from(200000));
      expect(estimate.preVerificationGas, BigInt.from(50000));
      expect(estimate.paymasterVerificationGasLimit, isNull);
      expect(estimate.paymasterPostOpGasLimit, isNull);
    });

    test('parseia a resposta com campos opcionais de paymaster', () async {
      when(() => mockTransport.call(any(), 'eth_estimateUserOperationGas', any()))
          .thenAnswer((_) async => {
                'callGasLimit': '0x186a0',
                'verificationGasLimit': '0x30d40',
                'preVerificationGas': '0xc350',
                'paymasterVerificationGasLimit': '0x1388',
                'paymasterPostOpGasLimit': '0x7d0',
              });

      final estimate = await client.estimateUserOperationGas(sampleOp());

      expect(estimate.paymasterVerificationGasLimit, BigInt.from(5000));
      expect(estimate.paymasterPostOpGasLimit, BigInt.from(2000));
    });

    test('propaga erro do transporte', () async {
      when(() => mockTransport.call(any(), any(), any()))
          .thenThrow(Exception('RPC error: boom'));

      expect(
        () => client.estimateUserOperationGas(sampleOp()),
        throwsException,
      );
    });
  });

  group('sendUserOperation', () {
    test('devolve o userOpHash', () async {
      when(() => mockTransport.call(any(), 'eth_sendUserOperation', any()))
          .thenAnswer((_) async => '0xuserOpHash');

      final hash = await client.sendUserOperation(sampleOp());

      expect(hash, '0xuserOpHash');
    });
  });

  group('getUserOperationReceipt', () {
    test('devolve null enquanto pendente (result sem error)', () async {
      when(() =>
              mockTransport.call(any(), 'eth_getUserOperationReceipt', any()))
          .thenAnswer((_) async => null);

      final receipt = await client.getUserOperationReceipt('0xuserOpHash');

      expect(receipt, isNull);
    });

    test('parseia o recibo quando já minerado', () async {
      when(() =>
              mockTransport.call(any(), 'eth_getUserOperationReceipt', any()))
          .thenAnswer((_) async => {
                'userOpHash': '0xuserOpHash',
                'success': true,
                'actualGasCost': '0x5af3107a4000',
                'actualGasUsed': '0x30d40',
                'receipt': {'transactionHash': '0xtxHash'},
              });

      final receipt = await client.getUserOperationReceipt('0xuserOpHash');

      expect(receipt, isNotNull);
      expect(receipt!.userOpHash, '0xuserOpHash');
      expect(receipt.success, isTrue);
      expect(receipt.actualGasCost, BigInt.parse('5af3107a4000', radix: 16));
      expect(receipt.actualGasUsed, BigInt.from(200000));
      expect(receipt.transactionHash, '0xtxHash');
    });

    test('propaga erro do transporte', () async {
      when(() => mockTransport.call(any(), any(), any()))
          .thenThrow(Exception('RPC error: boom'));

      expect(
        () => client.getUserOperationReceipt('0xuserOpHash'),
        throwsException,
      );
    });
  });
}

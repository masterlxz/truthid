import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/user_operation_signer.dart';
import 'package:truthid_mobile/utils/user_operation.dart';

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

Uint8List _bytes(String hex) => hexToBytes(hex);

// Mesmo vetor `no_factory_no_paymaster` de `user_operation_test.dart`
// (14.9.2, validado byte a byte contra o viem) — reaproveitado aqui pra
// confirmar que `signUserOperation` manda pro DeviceKeyService o hash certo,
// sem precisar cruzar de novo com o viem.
UserOperationV07 _buildOp() => UserOperationV07(
      sender:
          EthereumAddress.fromHex('0x1234567890123456789012345678901234567890'),
      nonce: BigInt.from(7),
      callData: _bytes('0xabcdef01'),
      callGasLimit: BigInt.from(100000),
      verificationGasLimit: BigInt.from(200000),
      preVerificationGas: BigInt.from(50000),
      maxFeePerGas: BigInt.from(1000000000),
      maxPriorityFeePerGas: BigInt.from(100000000),
    );

const _entryPoint = entryPointV07Address;
final _chainId = BigInt.from(8453);
const _expectedUserOpHashHex =
    '0xae94190d47190ec9ce40f9a5e0f3aa9397208df172050e749446ced9072ba28b';

void main() {
  late MockDeviceKeyService mockKeyService;

  setUpAll(() {
    registerFallbackValue(Uint8List(32));
  });

  setUp(() {
    mockKeyService = MockDeviceKeyService();
  });

  test('assina o userOpHash correto e anexa a assinatura na cópia devolvida',
      () async {
    final dummySignatureHex = '0x${'11' * 65}';
    when(() => mockKeyService.signHash(any()))
        .thenAnswer((_) async => dummySignatureHex);

    final op = _buildOp();

    final signedOp = await signUserOperation(
      userOperation: op,
      entryPoint: EthereumAddress.fromHex(_entryPoint),
      chainId: _chainId,
      deviceKeyService: mockKeyService,
    );

    final capturedHash =
        verify(() => mockKeyService.signHash(captureAny())).captured.single
            as Uint8List;
    expect(bytesToHex(capturedHash, include0x: true), _expectedUserOpHashHex);

    expect(signedOp.signature, hexToBytes(dummySignatureHex));
    expect(signedOp.signature.length, 65);

    // Resto da UserOperation permanece intacto.
    expect(signedOp.sender, op.sender);
    expect(signedOp.nonce, op.nonce);
    expect(signedOp.callData, op.callData);
    expect(signedOp.callGasLimit, op.callGasLimit);
    expect(signedOp.verificationGasLimit, op.verificationGasLimit);
    expect(signedOp.preVerificationGas, op.preVerificationGas);
    expect(signedOp.maxFeePerGas, op.maxFeePerGas);
    expect(signedOp.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
  });

  test('propaga erro se DeviceKeyService.signHash falhar', () async {
    when(() => mockKeyService.signHash(any()))
        .thenThrow(Exception('secure storage indisponível'));

    expect(
      () => signUserOperation(
        userOperation: _buildOp(),
        entryPoint: EthereumAddress.fromHex(_entryPoint),
        chainId: _chainId,
        deviceKeyService: mockKeyService,
      ),
      throwsException,
    );
  });
}

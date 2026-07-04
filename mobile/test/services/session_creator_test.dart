import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/pimlico_bundler_client.dart';
import 'package:truthid_mobile/services/session_creator.dart';
import 'package:truthid_mobile/utils/user_operation.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockPimlicoBundlerClient extends Mock implements PimlicoBundlerClient {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

UserOperationV07 _fakeUserOp() => UserOperationV07(
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

// Selector de `execute(address,uint256,bytes)` — mesma convenção usada em
// blockchain_service.dart pra calcular o topic de IdentityCreated: keccak256
// da assinatura da função, primeiros 4 bytes.
Uint8List _executeSelector() => keccak256(
      Uint8List.fromList(utf8.encode('execute(address,uint256,bytes)')),
    ).sublist(0, 4);

void main() {
  late MockBlockchainService mockBlockchain;
  late MockPimlicoBundlerClient mockBundler;
  late MockDeviceKeyService mockKeyService;
  late SessionCreator sessionCreator;

  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');
  final devicePubKey = EthereumAddress.fromHex(
      '0x9999999999999999999999999999999999999999');
  final sessionHash =
      keccak256(Uint8List.fromList(utf8.encode('test-nonce')));
  // r||s||v de 65 bytes — não precisa ser uma assinatura válida de verdade
  // pra este teste: SessionCreator só reparte os bytes, quem valida
  // criptograficamente é o contrato (fora do escopo deste teste unitário).
  final sessionSignatureHex = '0x${'ab' * 32}${'cd' * 32}1b';

  final dummyUserOpSignature = '0x${'11' * 65}';

  setUpAll(() {
    registerFallbackValue(_fakeUserOp());
    registerFallbackValue(smartAccountAddress);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockBundler = MockPimlicoBundlerClient();
    mockKeyService = MockDeviceKeyService();

    sessionCreator = SessionCreator(
      bundlerClient: mockBundler,
      blockchainService: mockBlockchain,
      deviceKeyService: mockKeyService,
      receiptPollInterval: Duration.zero,
      receiptPollMaxAttempts: 2,
    );

    when(() => mockBlockchain.getSmartAccountNonce(any()))
        .thenAnswer((_) async => BigInt.from(3));
    when(() => mockBundler.getUserOperationGasPrice()).thenAnswer(
      (_) async => UserOperationGasPrice(
        maxFeePerGas: BigInt.from(2000000000),
        maxPriorityFeePerGas: BigInt.from(1000000000),
      ),
    );
    when(() => mockBundler.estimateUserOperationGas(any())).thenAnswer(
      (_) async => UserOperationGasEstimate(
        callGasLimit: BigInt.from(100000),
        verificationGasLimit: BigInt.from(200000),
        preVerificationGas: BigInt.from(50000),
      ),
    );
    when(() => mockBundler.sendUserOperation(any()))
        .thenAnswer((_) async => '0xUserOpHashXYZ');
    when(() => mockKeyService.signHash(any()))
        .thenAnswer((_) async => dummyUserOpSignature);
  });

  test('monta, assina e envia a UserOp, e devolve o recibo confirmado',
      () async {
    when(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
        .thenAnswer((_) async => UserOperationReceipt(
              userOpHash: '0xUserOpHashXYZ',
              success: true,
              actualGasCost: BigInt.from(1000),
              actualGasUsed: BigInt.from(90000),
              transactionHash: '0xTxHash',
            ));

    final result = await sessionCreator.createSession(
      identityId: BigInt.one,
      smartAccountAddress: smartAccountAddress,
      sessionHash: sessionHash,
      devicePubKey: devicePubKey,
      sessionSignatureHex: sessionSignatureHex,
    );

    expect(result.userOpHash, '0xUserOpHashXYZ');
    expect(result.transactionHash, '0xTxHash');

    verify(() => mockBlockchain.getSmartAccountNonce(smartAccountAddress))
        .called(1);
    verify(() => mockBundler.getUserOperationGasPrice()).called(1);
    verify(() => mockKeyService.signHash(any())).called(1);

    // A UserOp final enviada ao bundler carrega o sender/nonce corretos, a
    // estimativa de gas e a assinatura de 65 bytes vinda do DeviceKeyService.
    final sentOp = verify(() => mockBundler.sendUserOperation(captureAny()))
        .captured
        .single as UserOperationV07;
    expect(sentOp.sender, smartAccountAddress);
    expect(sentOp.nonce, BigInt.from(3));
    expect(sentOp.callGasLimit, BigInt.from(100000));
    expect(sentOp.verificationGasLimit, BigInt.from(200000));
    expect(sentOp.preVerificationGas, BigInt.from(50000));
    expect(sentOp.signature, hexToBytes(dummyUserOpSignature));

    // callData é `execute(SessionRegistry, 0, createSession(...))` —
    // confirma o selector de `execute`, sem reimplementar o decoder ABI
    // completo (web3dart.encodeCall já é usado em produção em outros pontos
    // do app sem cross-check adicional).
    expect(sentOp.callData.sublist(0, 4), _executeSelector());
  });

  test(
      'a estimativa de gas usa uma UserOp com gas zerado e assinatura placeholder',
      () async {
    when(() => mockBundler.getUserOperationReceipt(any()))
        .thenAnswer((_) async => null);

    await sessionCreator.createSession(
      identityId: BigInt.one,
      smartAccountAddress: smartAccountAddress,
      sessionHash: sessionHash,
      devicePubKey: devicePubKey,
      sessionSignatureHex: sessionSignatureHex,
    );

    final estimatedOp =
        verify(() => mockBundler.estimateUserOperationGas(captureAny()))
            .captured
            .single as UserOperationV07;
    expect(estimatedOp.callGasLimit, BigInt.zero);
    expect(estimatedOp.verificationGasLimit, BigInt.zero);
    expect(estimatedOp.preVerificationGas, BigInt.zero);
    expect(estimatedOp.signature.length, 65);
  });

  test('devolve transactionHash nulo se o recibo não confirmar a tempo',
      () async {
    when(() => mockBundler.getUserOperationReceipt(any()))
        .thenAnswer((_) async => null);

    final result = await sessionCreator.createSession(
      identityId: BigInt.one,
      smartAccountAddress: smartAccountAddress,
      sessionHash: sessionHash,
      devicePubKey: devicePubKey,
      sessionSignatureHex: sessionSignatureHex,
    );

    expect(result.userOpHash, '0xUserOpHashXYZ');
    expect(result.transactionHash, isNull);
    verify(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
        .called(2); // receiptPollMaxAttempts configurado pra 2 neste teste
  });

  test('propaga erro se o envio ao bundler falhar', () async {
    when(() => mockBundler.sendUserOperation(any()))
        .thenThrow(Exception('bundler rejected the UserOperation'));

    expect(
      () => sessionCreator.createSession(
        identityId: BigInt.one,
        smartAccountAddress: smartAccountAddress,
        sessionHash: sessionHash,
        devicePubKey: devicePubKey,
        sessionSignatureHex: sessionSignatureHex,
      ),
      throwsException,
    );
  });
}

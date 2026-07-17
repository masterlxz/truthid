import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart'
    show ContractAbi, DeployedContract, EthereumAddress;

import 'package:truthid_mobile/contracts/abis.dart';
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
    // 2 chamadas: uma assinatura real "descartável" sobre a UserOp com gas
    // zerado (usada só na estimativa, pra não subestimar o AA26 — ver
    // session_creator.dart) e a assinatura final sobre a UserOp com os
    // valores de gas já preenchidos.
    verify(() => mockKeyService.signHash(any())).called(2);

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
      'a estimativa de gas usa uma UserOp com gas zerado mas assinatura real da device key',
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
    // Não pode ser um placeholder zerado (v=0): TruthIDAccount rejeitaria a
    // assinatura antes até de chamar ecrecover, subestimando o gas de
    // verificação real (causa raiz do AA26 achado na Sessão 114).
    expect(estimatedOp.signature, hexToBytes(dummyUserOpSignature));
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

  group('revokeSession', () {
    // Selector de `revokeSession(bytes32)` — mesma convenção de _executeSelector.
    Uint8List revokeSelector() => keccak256(
          Uint8List.fromList(utf8.encode('revokeSession(bytes32)')),
        ).sublist(0, 4);

    test('monta, assina e envia a UserOp de revogação, e devolve o recibo',
        () async {
      when(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
          .thenAnswer((_) async => UserOperationReceipt(
                userOpHash: '0xUserOpHashXYZ',
                success: true,
                actualGasCost: BigInt.from(1000),
                actualGasUsed: BigInt.from(90000),
                transactionHash: '0xTxHash',
              ));

      final result = await sessionCreator.revokeSession(
        smartAccountAddress: smartAccountAddress,
        sessionHash: sessionHash,
      );

      expect(result.userOpHash, '0xUserOpHashXYZ');
      expect(result.transactionHash, '0xTxHash');

      verify(() => mockBlockchain.getSmartAccountNonce(smartAccountAddress))
          .called(1);
      // 2 chamadas por operação (assinatura real usada na estimativa +
      // assinatura final) — ver comentário equivalente no teste de createSession.
      verify(() => mockKeyService.signHash(any())).called(2);

      final sentOp = verify(() => mockBundler.sendUserOperation(captureAny()))
          .captured
          .single as UserOperationV07;
      expect(sentOp.sender, smartAccountAddress);

      // callData é `execute(SessionRegistry, 0, revokeSession(hash))` —
      // confirma os dois selectors sem reimplementar o decoder ABI completo.
      expect(sentOp.callData.sublist(0, 4), _executeSelector());
      // O innerCallData (revokeSession) fica embutido no encoding do
      // `execute` — busca o selector de revokeSession em algum lugar do
      // callData final, já que o offset exato depende do encoding do bytes.
      final callDataHex = bytesToHex(sentOp.callData);
      expect(callDataHex.contains(bytesToHex(revokeSelector())), isTrue);
    });

    test('propaga erro se o envio ao bundler falhar', () async {
      when(() => mockBundler.sendUserOperation(any()))
          .thenThrow(Exception('bundler rejected the UserOperation'));

      expect(
        () => sessionCreator.revokeSession(
          smartAccountAddress: smartAccountAddress,
          sessionHash: sessionHash,
        ),
        throwsException,
      );
    });
  });

  group('withdraw', () {
    final destination = EthereumAddress.fromHex(
        '0xcccccccccccccccccccccccccccccccccccccccc');
    final amountWei = BigInt.from(500000000000000000); // 0.5 ETH

    test('monta, assina e envia a UserOp de saque com o value correto',
        () async {
      when(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
          .thenAnswer((_) async => UserOperationReceipt(
                userOpHash: '0xUserOpHashXYZ',
                success: true,
                actualGasCost: BigInt.from(1000),
                actualGasUsed: BigInt.from(90000),
                transactionHash: '0xTxHash',
              ));

      final result = await sessionCreator.withdraw(
        smartAccountAddress: smartAccountAddress,
        destination: destination,
        amountWei: amountWei,
      );

      expect(result.userOpHash, '0xUserOpHashXYZ');
      expect(result.transactionHash, '0xTxHash');

      verify(() => mockBlockchain.getSmartAccountNonce(smartAccountAddress))
          .called(1);

      final sentOp = verify(() => mockBundler.sendUserOperation(captureAny()))
          .captured
          .single as UserOperationV07;
      expect(sentOp.sender, smartAccountAddress);

      // Reconstrói o callData esperado via encodeCall com os mesmos
      // argumentos — mais confiável que recortar offsets manualmente, já
      // que aqui (ao contrário de createSession/revokeSession) o `value`
      // enviado a `execute` varia e precisa ser conferido também, não só
      // o `dest`.
      final truthidAccount = DeployedContract(
        ContractAbi.fromJson(truthidAccountAbi, 'TruthIDAccount'),
        smartAccountAddress,
      );
      final expectedCallData = truthidAccount.function('execute').encodeCall([
        destination,
        amountWei,
        Uint8List(0),
      ]);
      expect(sentOp.callData, expectedCallData);
    });

    test('propaga erro se o envio ao bundler falhar', () async {
      when(() => mockBundler.sendUserOperation(any()))
          .thenThrow(Exception('bundler rejected the UserOperation'));

      expect(
        () => sessionCreator.withdraw(
          smartAccountAddress: smartAccountAddress,
          destination: destination,
          amountWei: amountWei,
        ),
        throwsException,
      );
    });
  });

  group('executeArbitraryCall', () {
    final dest = EthereumAddress.fromHex(
        '0xdddddddddddddddddddddddddddddddddddddddd');
    final value = BigInt.from(1000000000000000); // 0.001 ETH
    final innerCallData =
        Uint8List.fromList([0xa9, 0x05, 0x9c, 0xbb, 0x01, 0x02]);

    test('monta, assina e envia a UserOp com dest/value/callData recebidos',
        () async {
      when(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
          .thenAnswer((_) async => UserOperationReceipt(
                userOpHash: '0xUserOpHashXYZ',
                success: true,
                actualGasCost: BigInt.from(1000),
                actualGasUsed: BigInt.from(90000),
                transactionHash: '0xTxHash',
              ));

      final result = await sessionCreator.executeArbitraryCall(
        smartAccountAddress: smartAccountAddress,
        dest: dest,
        value: value,
        innerCallData: innerCallData,
      );

      expect(result.userOpHash, '0xUserOpHashXYZ');
      expect(result.transactionHash, '0xTxHash');

      verify(() => mockBlockchain.getSmartAccountNonce(smartAccountAddress))
          .called(1);
      // 2 chamadas por operação (assinatura real usada na estimativa +
      // assinatura final) — ver comentário equivalente no teste de createSession.
      verify(() => mockKeyService.signHash(any())).called(2);

      final sentOp = verify(() => mockBundler.sendUserOperation(captureAny()))
          .captured
          .single as UserOperationV07;
      expect(sentOp.sender, smartAccountAddress);

      // Reconstrói o callData esperado via encodeCall com os mesmos
      // argumentos recebidos de fora — mesma técnica do teste de withdraw,
      // já que aqui dest/value/callData variam todos juntos.
      final truthidAccount = DeployedContract(
        ContractAbi.fromJson(truthidAccountAbi, 'TruthIDAccount'),
        smartAccountAddress,
      );
      final expectedCallData = truthidAccount.function('execute').encodeCall([
        dest,
        value,
        innerCallData,
      ]);
      expect(sentOp.callData, expectedCallData);
    });

    test('propaga erro se o envio ao bundler falhar', () async {
      when(() => mockBundler.sendUserOperation(any()))
          .thenThrow(Exception('bundler rejected the UserOperation'));

      expect(
        () => sessionCreator.executeArbitraryCall(
          smartAccountAddress: smartAccountAddress,
          dest: dest,
          value: value,
          innerCallData: innerCallData,
        ),
        throwsException,
      );
    });
  });

  group('updateVault', () {
    // Selector de `updateVault(string,bytes32)` — mesma convenção de _executeSelector.
    Uint8List updateVaultSelector() => keccak256(
          Uint8List.fromList(utf8.encode('updateVault(string,bytes32)')),
        ).sublist(0, 4);

    const cid = 'QmTestCid123';
    final contentHashHex = '0x${'ab' * 32}';

    test('monta, assina e envia a UserOp de publicação, e devolve o recibo',
        () async {
      when(() => mockBundler.getUserOperationReceipt('0xUserOpHashXYZ'))
          .thenAnswer((_) async => UserOperationReceipt(
                userOpHash: '0xUserOpHashXYZ',
                success: true,
                actualGasCost: BigInt.from(1000),
                actualGasUsed: BigInt.from(90000),
                transactionHash: '0xTxHash',
              ));

      final result = await sessionCreator.updateVault(
        smartAccountAddress: smartAccountAddress,
        cid: cid,
        contentHashHex: contentHashHex,
      );

      expect(result.userOpHash, '0xUserOpHashXYZ');
      expect(result.transactionHash, '0xTxHash');

      verify(() => mockBlockchain.getSmartAccountNonce(smartAccountAddress))
          .called(1);
      // 2 chamadas por operação (assinatura real usada na estimativa +
      // assinatura final) — ver comentário equivalente no teste de createSession.
      verify(() => mockKeyService.signHash(any())).called(2);

      final sentOp = verify(() => mockBundler.sendUserOperation(captureAny()))
          .captured
          .single as UserOperationV07;
      expect(sentOp.sender, smartAccountAddress);

      // callData é `execute(VaultRegistry, 0, updateVault(cid, contentHash))`.
      expect(sentOp.callData.sublist(0, 4), _executeSelector());
      final callDataHex = bytesToHex(sentOp.callData);
      expect(callDataHex.contains(bytesToHex(updateVaultSelector())), isTrue);
    });

    test('propaga erro se o envio ao bundler falhar', () async {
      when(() => mockBundler.sendUserOperation(any()))
          .thenThrow(Exception('bundler rejected the UserOperation'));

      expect(
        () => sessionCreator.updateVault(
          smartAccountAddress: smartAccountAddress,
          cid: cid,
          contentHashHex: contentHashHex,
        ),
        throwsException,
      );
    });
  });
}

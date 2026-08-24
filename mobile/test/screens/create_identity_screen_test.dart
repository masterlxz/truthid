import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/screens/create_identity_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/vault_key_service.dart';
import 'package:truthid_mobile/services/wallet_connect_service.dart';

class MockWalletConnectService extends Mock implements WalletConnectService {}

class MockBlockchainService extends Mock implements BlockchainService {}

class MockVaultKeyService extends Mock implements VaultKeyService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class _FakeBuildContext extends Fake implements BuildContext {}

// Assinatura de 65 bytes válida (r||s||v) — só precisa ter o tamanho certo,
// parseSignatureHex não valida a matemática da curva.
String _fakeSignatureHex() =>
    '0x${'11' * 32}${'22' * 32}1b';

void main() {
  late MockWalletConnectService mockWc;
  late MockBlockchainService mockBlockchain;
  late MockVaultKeyService mockVaultKey;
  late MockLocalStorageService mockStorage;
  late CreateIdentityFlow flow;
  int notifyCount = 0;

  final owner =
      EthereumAddress.fromHex('0x1111111111111111111111111111111111111111');
  final controller =
      EthereumAddress.fromHex('0x2222222222222222222222222222222222222222');

  setUpAll(() {
    registerFallbackValue(owner);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_FakeBuildContext());
  });

  setUp(() {
    mockWc = MockWalletConnectService();
    mockBlockchain = MockBlockchainService();
    mockVaultKey = MockVaultKeyService();
    mockStorage = MockLocalStorageService();
    notifyCount = 0;

    flow = CreateIdentityFlow(
      onChange: () => notifyCount++,
      walletConnect: mockWc,
      blockchain: mockBlockchain,
      vaultKeyService: mockVaultKey,
      storage: mockStorage,
    );

    when(() => mockWc.connectedAddress).thenReturn(owner.hex);
    when(() => mockWc.dispose()).thenAnswer((_) async {});

    // checkAvailability/createIdentity/deriveVaultKey leem o endereço já
    // cacheado no flow (populado por connectWallet em produção) — os testes
    // desses métodos simulam "já conectado" direto, sem precisar rodar
    // connectWallet primeiro.
    flow.connectedAddress = owner.hex;
  });

  group('connectWallet — guarda de disparo duplo', () {
    testWidgets('2 chamadas concorrentes só abrem a modal 1 vez',
        (tester) async {
      // Sem Future.delayed de propósito: testWidgets roda num relógio falso
      // (não avança sozinho sem tester.pump()) — um delay real aqui trava o
      // teste pra sempre. Não precisa de delay nenhum pra provar a guarda:
      // _busy já é setado de forma síncrona antes do 1º await em
      // connectWallet, então a 2ª chamada já acha _busy==true não importa
      // quão rápido a 1ª resolve.
      var openCalls = 0;
      when(() => mockWc.init(any())).thenAnswer((_) async {});
      when(() => mockWc.openConnectModal()).thenAnswer((_) async {
        openCalls++;
      });

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final context = tester.element(find.byType(Scaffold));

      final f1 = flow.connectWallet(context);
      final f2 = flow.connectWallet(context); // dispara enquanto f1 ainda roda
      await Future.wait([f1, f2]);

      expect(openCalls, 1);
    });
  });

  group('checkAvailability', () {
    test('username livre e wallet sem identidade — available', () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockBlockchain.getUsernameByController(controller))
          .thenAnswer((_) async => '');
      when(() => mockBlockchain.isUsernameTaken('alice'))
          .thenAnswer((_) async => false);

      final result = await flow.checkAvailability('alice');

      expect(result, UsernameAvailability.available);
      expect(flow.predictedAddress, controller);
    });

    test('username já em uso — taken', () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockBlockchain.getUsernameByController(controller))
          .thenAnswer((_) async => '');
      when(() => mockBlockchain.isUsernameTaken('alice'))
          .thenAnswer((_) async => true);

      final result = await flow.checkAvailability('alice');

      expect(result, UsernameAvailability.taken);
    });

    test('wallet já controla uma identidade — alreadyHasIdentity', () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockBlockchain.getUsernameByController(controller))
          .thenAnswer((_) async => 'bob');

      final result = await flow.checkAvailability('alice');

      expect(result, UsernameAvailability.alreadyHasIdentity);
      // Já sabe que a wallet tem dono — não precisa checar o username novo.
      verifyNever(() => mockBlockchain.isUsernameTaken(any()));
    });

    test('sempre volta pro step form ao terminar (sucesso ou não)', () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockBlockchain.getUsernameByController(controller))
          .thenAnswer((_) async => '');
      when(() => mockBlockchain.isUsernameTaken('alice'))
          .thenAnswer((_) async => false);

      await flow.checkAvailability('alice');

      expect(flow.step, CreateIdentityStep.form);
    });
  });

  group('createIdentity — sequência completa (happy path)', () {
    setUp(() {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockWc.personalSign(any()))
          .thenAnswer((_) async => _fakeSignatureHex());
      when(() => mockBlockchain.buildCreateIdentityCalldata(
            username: any(named: 'username'),
            controller: any(named: 'controller'),
            v: any(named: 'v'),
            r: any(named: 'r'),
            s: any(named: 's'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildCreateAccountCalldata(any()))
          .thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer(
          (_) async => IdentityInfo(id: BigInt.from(42), controller: controller));
      when(() => mockStorage.savePairedIdentity('42')).thenAnswer((_) async {});
    });

    test('termina em done e salva o identityId', () async {
      await flow.createIdentity(username: 'alice', fundingEthText: '0.001');

      expect(flow.step, CreateIdentityStep.done);
      expect(flow.errorMessage, isNull);
      expect(flow.identityId, BigInt.from(42));
      verify(() => mockStorage.savePairedIdentity('42')).called(1);
    });

    test('assina o consentimento e as 2 transações principais', () async {
      await flow.createIdentity(username: 'alice', fundingEthText: '0.001');

      // 1 assinatura (consentimento) — a da vault key é um passo separado
      // (deriveVaultKey), não faz parte desta sequência.
      verify(() => mockWc.personalSign(any())).called(1);
      verify(() => mockWc.sendTransaction(
            to: BlockchainService.identityRegistryAddress,
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).called(1);
      verify(() => mockWc.sendTransaction(
            to: BlockchainService.truthidAccountFactoryAddress,
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).called(1);
    });

    test('financia o endereço previsto da smart account', () async {
      await flow.createIdentity(username: 'alice', fundingEthText: '0.001');

      verify(() => mockWc.sendTransaction(
            to: controller.hex,
            valueWei: BigInt.from(1000000000000000), // 0.001 ETH em wei
            data: null,
          )).called(1);
    });

    test('funding "0" não dispara transação de financiamento', () async {
      await flow.createIdentity(username: 'alice', fundingEthText: '0');

      verifyNever(() => mockWc.sendTransaction(
            to: controller.hex,
            valueWei: any(named: 'valueWei'),
            data: null,
          ));
    });
  });

  group('createIdentity — guarda de disparo duplo', () {
    test('2 chamadas concorrentes só rodam a sequência 1 vez', () async {
      var signCalls = 0;
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockWc.personalSign(any())).thenAnswer((_) async {
        signCalls++;
        await Future.delayed(const Duration(milliseconds: 30));
        return _fakeSignatureHex();
      });
      when(() => mockBlockchain.buildCreateIdentityCalldata(
            username: any(named: 'username'),
            controller: any(named: 'controller'),
            v: any(named: 'v'),
            r: any(named: 'r'),
            s: any(named: 's'),
          )).thenReturn(Uint8List(4));
      when(() => mockBlockchain.buildCreateAccountCalldata(any()))
          .thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => true);
      when(() => mockBlockchain.getIdentityByUsername(any())).thenAnswer(
          (_) async => IdentityInfo(id: BigInt.one, controller: controller));
      when(() => mockStorage.savePairedIdentity(any())).thenAnswer((_) async {});

      final f1 = flow.createIdentity(username: 'alice', fundingEthText: '0');
      final f2 = flow.createIdentity(username: 'alice', fundingEthText: '0');
      await Future.wait([f1, f2]);

      expect(signCalls, 1);
    });
  });

  group('createIdentity — caminho de erro', () {
    test('transação revertida vira errorMessage e volta pro form', () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockWc.personalSign(any()))
          .thenAnswer((_) async => _fakeSignatureHex());
      when(() => mockBlockchain.buildCreateIdentityCalldata(
            username: any(named: 'username'),
            controller: any(named: 'controller'),
            v: any(named: 'v'),
            r: any(named: 'r'),
            s: any(named: 's'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => false); // reverteu

      await flow.createIdentity(username: 'alice', fundingEthText: '0');

      expect(flow.step, CreateIdentityStep.form);
      expect(flow.errorMessage, isNotNull);
      verifyNever(() => mockStorage.savePairedIdentity(any()));
    });

    test('libera a guarda depois de um erro — dá pra tentar de novo',
        () async {
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenThrow(Exception('RPC indisponível'));

      await flow.createIdentity(username: 'alice', fundingEthText: '0');
      expect(flow.isBusy, isFalse);

      // 2ª tentativa deveria rodar de verdade, não ser descartada pela guarda.
      when(() => mockBlockchain.predictSmartAccountAddress(owner))
          .thenAnswer((_) async => controller);
      when(() => mockWc.personalSign(any()))
          .thenAnswer((_) async => _fakeSignatureHex());
      when(() => mockBlockchain.buildCreateIdentityCalldata(
            username: any(named: 'username'),
            controller: any(named: 'controller'),
            v: any(named: 'v'),
            r: any(named: 'r'),
            s: any(named: 's'),
          )).thenReturn(Uint8List(4));
      when(() => mockWc.sendTransaction(
            to: any(named: 'to'),
            valueWei: any(named: 'valueWei'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => '0xtxhash');
      when(() => mockBlockchain.isTransactionConfirmed(any()))
          .thenAnswer((_) async => false);

      await flow.createIdentity(username: 'alice', fundingEthText: '0');
      verify(() => mockWc.personalSign(any())).called(1);
    });
  });

  group('deriveVaultKey', () {
    test('sucesso — persiste e marca vaultKeyDerived', () async {
      when(() => mockWc.personalSign(any()))
          .thenAnswer((_) async => _fakeSignatureHex());
      when(() => mockVaultKey.deriveAndStoreFromWalletSignature(
            r: any(named: 'r'),
            s: any(named: 's'),
            v: any(named: 'v'),
          )).thenAnswer((_) async {});

      await flow.deriveVaultKey();

      expect(flow.vaultKeyDerived, isTrue);
      expect(flow.errorMessage, isNull);
    });

    test('assina exatamente a mensagem fixa "TruthID Vault Key v1"', () async {
      Uint8List? signedBytes;
      when(() => mockWc.personalSign(any())).thenAnswer((invocation) async {
        signedBytes = invocation.positionalArguments[0] as Uint8List;
        return _fakeSignatureHex();
      });
      when(() => mockVaultKey.deriveAndStoreFromWalletSignature(
            r: any(named: 'r'),
            s: any(named: 's'),
            v: any(named: 'v'),
          )).thenAnswer((_) async {});

      await flow.deriveVaultKey();

      expect(String.fromCharCodes(signedBytes!), 'TruthID Vault Key v1');
    });
  });
}

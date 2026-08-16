import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'package:truthid_mobile/screens/vault_edit_approval_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/remote_signer_lan_server.dart';
import 'package:truthid_mobile/services/vault_edit_content_cipher_service.dart';
import 'package:truthid_mobile/services/vault_edit_dead_drop_polling_service.dart';
import 'package:truthid_mobile/services/vault_publish_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockVaultEditDeadDropPollingService extends Mock
    implements VaultEditDeadDropPollingService {}

class MockVaultRepository extends Mock implements VaultRepository {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockBlockchainService extends Mock implements BlockchainService {}

class MockVaultPublishService extends Mock implements VaultPublishService {}

void main() {
  late MockRemoteSignerLanServer mockLanServer;
  late MockVaultEditDeadDropPollingService mockDeadDropPollingService;
  late MockVaultRepository mockRepository;
  late MockLocalStorageService mockStorage;
  late MockBlockchainService mockBlockchain;
  late MockVaultPublishService mockPublishService;

  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey = '0x02${'ab' * 32}';
  final smartAccountAddress = EthereumAddress.fromHex(
      '0xabababababababababababababababababababab');
  // sessionId de teste, formato do QR real (hex, 16 bytes) —
  // deriveVaultEditContentKey faz hexToBytes sobre isso.
  const testSessionId = '000102030405060708090a0b0c0d0e0f';

  Map<String, dynamic> validPayload({
    String sessionId = testSessionId,
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
    String appName = 'TruthID Extension',
  }) =>
      {
        'action': 'truthid-vault-edit',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
        'appName': appName,
      };

  Future<Uint8List> encryptProposal(Map<String, dynamic> proposal) async {
    final key = deriveVaultEditContentKey(testSessionId);
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(proposal)));
    return encryptVaultEditContent(plaintext, key);
  }

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DateTime.now());
    registerFallbackValue(smartAccountAddress);
    registerFallbackValue(VaultEntry(
      id: 'fallback-id',
      site: 'fallback.example',
      url: '',
      username: 'fallback',
      password: 'fallback',
      notes: '',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));
  });

  setUp(() {
    mockLanServer = MockRemoteSignerLanServer();
    mockDeadDropPollingService = MockVaultEditDeadDropPollingService();
    mockRepository = MockVaultRepository();
    mockStorage = MockLocalStorageService();
    mockBlockchain = MockBlockchainService();
    mockPublishService = MockVaultPublishService();

    // `dispose()` (achado #7) chama `_lanServer.stop()` incondicionalmente
    // em toda desmontagem da tela — inclusive a que o próprio binding de
    // teste faz entre um `testWidgets` e o outro. Precisa de stub global
    // (não só nos testes que checam o comportamento de dispose de propósito),
    // senão qualquer teste quebra com "Null is not a subtype of Future<void>"
    // (mocktail: método sem stub configurado devolve null por padrão).
    when(() => mockLanServer.stop()).thenAnswer((_) async {});

    // Por padrão o dead-drop nunca acha nada (resolve `null` de cara) — os
    // testes que exercitam a fase 1 (recebimento) continuam controlando o
    // resultado via `mockLanServer`, como já faziam antes deste canal
    // existir. Precisa resolver (não travar pra sempre) pro cenário de
    // timeout continuar funcionando: `_receiveViaAnyChannel` só decide
    // "nada chegou" quando os DOIS canais dizem `null`.
    when(() => mockDeadDropPollingService.pollUntil(any(), any(), isCancelled: any(named: 'isCancelled')))
        .thenAnswer((_) async => null);

    when(() => mockStorage.getPairedIdentityId())
        .thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer(
      (_) async =>
          IdentityInfo(id: BigInt.one, controller: smartAccountAddress),
    );
    when(() => mockRepository.addEntry(
          site: any(named: 'site'),
          url: any(named: 'url'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          notes: any(named: 'notes'),
          passkey: any(named: 'passkey'),
        )).thenAnswer((_) async => VaultEntry(
          id: 'new-id',
          site: 'example.com',
          url: '',
          username: 'alice',
          password: 'hunter2',
          notes: '',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ));
    when(() => mockPublishService.publish(any())).thenAnswer(
      (_) async => const VaultPublishResult(
        cid: 'bafy123',
        contentHash: '0xhash',
      ),
    );
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                child: const Text('Home'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VaultEditApprovalScreen(
                      payload: payload,
                      lanServer: mockLanServer,
                      deadDropPollingService: mockDeadDropPollingService,
                      repository: mockRepository,
                      localStorageService: mockStorage,
                      blockchainService: mockBlockchain,
                      publishService: mockPublishService,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpAndOpen(WidgetTester tester, Map<String, dynamic> payload) async {
    await tester.pumpWidget(buildScreen(payload));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
  }

  group('validação do schema v1 do QR', () {
    testWidgets('payload sem sessionId mostra erro', (tester) async {
      await pumpAndOpen(tester, validPayload(sessionId: ''));
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload sem ephemeralPubKey mostra erro', (tester) async {
      await pumpAndOpen(tester, validPayload(ephemeralPubKey: ''));
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('schema version desconhecida mostra erro', (tester) async {
      await pumpAndOpen(tester, validPayload(v: 2));
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('QR expirado mostra erro', (tester) async {
      await pumpAndOpen(
        tester,
        validPayload(
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1))),
      );
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('appName vazio mostra erro', (tester) async {
      await pumpAndOpen(tester, validPayload(appName: ''));
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });
  });

  group('fase 1 — recebimento do conteúdo', () {
    testWidgets('timeout mostra "Nothing arrived"', (tester) async {
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => null);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('Nothing arrived'), findsOneWidget);
    });

    testWidgets('proposta recebida e decifrada mostra a tela de aprovação',
        (tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': 'https://example.com',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'createdAtMs': 0,
      });
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('TruthID Extension wants to save a new credential'),
          findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('+ passkey'), findsNothing);
    });

    testWidgets('proposta com passkey mostra o badge "+ passkey"',
        (tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': '',
        'username': 'alice',
        'password': '',
        'notes': '',
        'passkey': {
          'rp_id': 'example.com',
          'credential_id_b64': 'AAAA',
          'user_handle_b64': 'BBBB',
          'private_key_hex': 'cc' * 32,
          'sign_count': 0,
          'created_at': 0,
        },
        'createdAtMs': 0,
      });
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('+ passkey'), findsOneWidget);
    });

    testWidgets(
        'dead-drop entrega a proposta quando a LAN nunca responde '
        '(corrida cross-network, item 6 do backlog)', (tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': 'https://example.com',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'createdAtMs': 0,
      });
      // LAN nunca resolve (celular numa rede diferente do PC) — só o
      // dead-drop entrega.
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) => Completer<Uint8List?>().future);
      when(() => mockDeadDropPollingService.pollUntil(any(), any(), isCancelled: any(named: 'isCancelled')))
          .thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('TruthID Extension wants to save a new credential'),
          findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets(
        'achado #7 do /code-review (S140): sair da tela libera a porta LAN '
        'e cancela o polling do dead-drop', (tester) async {
      bool Function()? capturedIsCancelled;
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) => Completer<Uint8List?>().future);
      when(() => mockLanServer.stop()).thenAnswer((_) async {});
      when(() => mockDeadDropPollingService.pollUntil(any(), any(),
              isCancelled: any(named: 'isCancelled')))
          .thenAnswer((invocation) {
        capturedIsCancelled = invocation.namedArguments[#isCancelled]
            as bool Function()?;
        return Completer<Uint8List?>().future;
      });

      // Não usa pumpAndOpen/pumpAndSettle aqui de propósito: a tela fica
      // travada em receivingContent (os dois canais nunca resolvem, por
      // desenho deste teste) — o `CircularProgressIndicator` indeterminado
      // dessa tela nunca "assenta", então `pumpAndSettle()` nunca convergiria
      // e o teste travaria. `pump()`/`pump(duration)` bastam pra abrir a
      // rota e completar a transição de push/pop sem esperar o spinner parar.
      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.tap(find.text('Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(capturedIsCancelled, isNotNull);
      expect(capturedIsCancelled!(), isFalse);

      await tester.pageBack();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      verify(() => mockLanServer.stop()).called(1);
      expect(capturedIsCancelled!(), isTrue);
    });

    testWidgets(
        'achado #3 do /code-review (S140): LAN lançando exceção não trava '
        'pra sempre — dead-drop ainda entrega', (tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': 'https://example.com',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'createdAtMs': 0,
      });
      // Mesmo StateError real que `RemoteSignerLanServer.receiveOnce` lança
      // quando as 5 portas candidatas já estão todas ligadas por outra tela.
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => throw StateError('nenhuma porta disponível'));
      when(() => mockDeadDropPollingService.pollUntil(any(), any(), isCancelled: any(named: 'isCancelled')))
          .thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('TruthID Extension wants to save a new credential'),
          findsOneWidget);
    });

    testWidgets(
        'achado #3 do /code-review (S140): LAN lançando exceção e dead-drop '
        'dando null resolve como timeout, não trava pra sempre',
        (tester) async {
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => throw StateError('nenhuma porta disponível'));
      when(() => mockDeadDropPollingService.pollUntil(any(), any(), isCancelled: any(named: 'isCancelled')))
          .thenAnswer((_) async => null);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('Nothing arrived'), findsOneWidget);
    });

    testWidgets('conteúdo cifrado com sessionId errado mostra erro',
        (tester) async {
      final wrongKey = deriveVaultEditContentKey('deadbeefdeadbeefdead'
          'beefdeadbeef');
      final blob = await encryptVaultEditContent(
        Uint8List.fromList(utf8.encode('{}')),
        wrongKey,
      );
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => blob);

      await pumpAndOpen(tester, validPayload());

      expect(find.textContaining('Failed to decrypt'), findsOneWidget);
    });
  });

  group('fase 2 — Approve', () {
    Future<void> pumpToApproval(WidgetTester tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': '',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'createdAtMs': 0,
      });
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());
    }

    testWidgets('persiste a entrada e publica, termina em "Saved"',
        (tester) async {
      await pumpToApproval(tester);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.addEntry(
            site: 'example.com',
            url: '',
            username: 'alice',
            password: 'hunter2',
            notes: '',
            passkey: null,
          )).called(1);
      verify(() => mockPublishService.publish(smartAccountAddress)).called(1);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets(
        'proposta com targetEntryId atualiza a entrada existente em vez de criar uma nova',
        (tester) async {
      final existingEntry = VaultEntry(
        id: 'existing-id',
        site: 'old-site.example',
        url: '',
        username: 'old-username',
        password: 'old-password',
        notes: 'old-notes',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [existingEntry]);
      when(() => mockRepository.updateEntry(any()))
          .thenAnswer((invocation) async => invocation.positionalArguments[0] as VaultEntry);

      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': '',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'targetEntryId': 'existing-id',
        'createdAtMs': 0,
      });
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepository.addEntry(
            site: any(named: 'site'),
            url: any(named: 'url'),
            username: any(named: 'username'),
            password: any(named: 'password'),
            notes: any(named: 'notes'),
            passkey: any(named: 'passkey'),
          ));
      final captured = verify(() => mockRepository.updateEntry(captureAny()))
          .captured
          .single as VaultEntry;
      expect(captured.id, 'existing-id');
      expect(captured.site, 'example.com');
      expect(captured.username, 'alice');
      expect(captured.password, 'hunter2');
      verify(() => mockPublishService.publish(smartAccountAddress)).called(1);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets(
        'duplo toque em Approve persiste a entrada só uma vez (M7, achado '
        'do /code-review high: _entryPersisted só era checado depois de um '
        'await, então 2 chamadas concorrentes passavam pela checagem antes '
        'da 1ª terminar de setá-lo)', (tester) async {
      await pumpToApproval(tester);

      await tester.tap(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.addEntry(
            site: 'example.com',
            url: '',
            username: 'alice',
            password: 'hunter2',
            notes: '',
            passkey: null,
          )).called(1);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('celular não pareado mostra erro e não persiste nada',
        (tester) async {
      when(() => mockStorage.getPairedIdentityId())
          .thenAnswer((_) async => null);

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.textContaining("isn't paired"), findsOneWidget);
      verifyNever(() => mockRepository.addEntry(
            site: any(named: 'site'),
            url: any(named: 'url'),
            username: any(named: 'username'),
            password: any(named: 'password'),
            notes: any(named: 'notes'),
            passkey: any(named: 'passkey'),
          ));
    });

    testWidgets(
        'identityId pareado mas username null resolve on-chain e aprova',
        (tester) async {
      // Achado real (Sessão 135, mesmo caso do wallet_screen.dart): o
      // celular já está pareado, mas o username nunca foi persistido — a
      // tela deve tentar resolver de novo, não reportar "não pareado".
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenAnswer((_) async => 'alice');
      when(() => mockStorage.savePairedUsername('alice'))
          .thenAnswer((_) async {});

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockBlockchain.getUsernameForIdentity(BigInt.one)).called(1);
      verify(() => mockStorage.savePairedUsername('alice')).called(1);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets(
        'identityId pareado, username null e resolução falha mostra erro '
        'específico (não "não pareado")', (tester) async {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenThrow(Exception('log scan timed out'));

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Still resolving'), findsOneWidget);
      expect(find.textContaining("isn't paired"), findsNothing);
      verifyNever(() => mockRepository.addEntry(
            site: any(named: 'site'),
            url: any(named: 'url'),
            username: any(named: 'username'),
            password: any(named: 'password'),
            notes: any(named: 'notes'),
            passkey: any(named: 'passkey'),
          ));
    });

    testWidgets(
        '"Try again" reaparece no erro (proposta já decifrada) e retenta '
        'sem duplicar a entrada', (tester) async {
      // Achado real (Sessão 135, ultrareview): antes deste fix, "Back" era
      // a única opção — descartava a proposta já decifrada pra sempre numa
      // falha transiente de rede. Simula falhar uma vez, depois funcionar.
      var callCount = 0;
      when(() => mockBlockchain.getIdentityByUsername('alice')).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('RPC timeout');
        return IdentityInfo(id: BigInt.one, controller: smartAccountAddress);
      });

      await pumpToApproval(tester);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Could not resolve'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      // addEntry só uma vez mesmo com 2 tentativas de _approve() — a 1ª
      // falhou DEPOIS de já ter persistido a entrada (getIdentityByUsername
      // é chamado depois de addEntry na 2ª leva do fluxo), retry não deve
      // duplicar.
      verify(() => mockRepository.addEntry(
            site: 'example.com',
            url: '',
            username: 'alice',
            password: 'hunter2',
            notes: '',
            passkey: null,
          )).called(1);
    });

    testWidgets(
        'erro de validação do QR (antes de decifrar) não mostra "Try again"',
        (tester) async {
      await pumpAndOpen(tester, validPayload(sessionId: ''));

      expect(find.textContaining('Invalid QR'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('sync em lote (P29)', () {
    Future<Uint8List> encryptBatch(List<Map<String, dynamic>> proposals) async {
      final key = deriveVaultEditContentKey(testSessionId);
      final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(proposals)));
      return encryptVaultEditContent(plaintext, key);
    }

    final proposalA = {
      'site': 'one.com',
      'url': '',
      'username': 'alice',
      'password': 'hunter2',
      'notes': '',
    };
    final proposalB = {
      'site': 'two.com',
      'url': '',
      'username': 'bob',
      'password': 'hunter3',
      'notes': '',
    };

    testWidgets(
        'conteúdo cifrado como lista mostra título pluralizado e uma card por proposta',
        (tester) async {
      final encrypted = await encryptBatch([proposalA, proposalB]);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(
        find.text('TruthID Extension wants to save 2 new credentials'),
        findsOneWidget,
      );
      expect(find.text('one.com'), findsOneWidget);
      expect(find.text('two.com'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('approve persiste as duas entradas e publica uma vez só',
        (tester) async {
      final encrypted = await encryptBatch([proposalA, proposalB]);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());
      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.addEntry(
            site: 'one.com',
            url: '',
            username: 'alice',
            password: 'hunter2',
            notes: '',
            passkey: null,
          )).called(1);
      verify(() => mockRepository.addEntry(
            site: 'two.com',
            url: '',
            username: 'bob',
            password: 'hunter3',
            notes: '',
            passkey: null,
          )).called(1);
      // 1 pin + 1 UserOperation pra N entradas, não N publishes — é isso que
      // faz "sync em lote" reduzir custo de gas, ver doc comment da tela.
      verify(() => mockPublishService.publish(smartAccountAddress)).called(1);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets(
        'retry depois de addEntry parcial não duplica a entrada já persistida',
        (tester) async {
      // Mesma ideia do teste equivalente de item único (ver grupo "fase 2 —
      // Approve"): a 1ª tentativa persiste as duas entradas (addEntry roda
      // pras duas, sem erro) mas falha depois, no publish() — um retry deve
      // pular o loop de addEntry inteiro (_persistedIndices já cobre os 2
      // índices) e só tentar publish() de novo.
      final encrypted = await encryptBatch([proposalA, proposalB]);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      var publishCallCount = 0;
      when(() => mockPublishService.publish(any())).thenAnswer((_) async {
        publishCallCount++;
        if (publishCallCount == 1) throw Exception('bundler timeout');
        return const VaultPublishResult(
          cid: 'bafy123',
          contentHash: '0xhash',
        );
      });

      await pumpAndOpen(tester, validPayload());
      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      verify(() => mockRepository.addEntry(
            site: 'one.com',
            url: '',
            username: 'alice',
            password: 'hunter2',
            notes: '',
            passkey: null,
          )).called(1);
      verify(() => mockRepository.addEntry(
            site: 'two.com',
            url: '',
            username: 'bob',
            password: 'hunter3',
            notes: '',
            passkey: null,
          )).called(1);
      expect(publishCallCount, 2);
    });

    testWidgets(
        'objeto único (sem lista) continua funcionando — SDK Dart ainda '
        'manda uma proposta por sessão', (tester) async {
      final encrypted = await encryptProposal(proposalA);
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      expect(find.text('TruthID Extension wants to save a new credential'),
          findsOneWidget);
      expect(find.text('one.com'), findsOneWidget);
    });
  });

  group('fase 2 — Reject', () {
    testWidgets('nunca persiste nem publica, só volta', (tester) async {
      final encrypted = await encryptProposal({
        'id': 'proposal-1',
        'site': 'example.com',
        'url': '',
        'username': 'alice',
        'password': 'hunter2',
        'notes': '',
        'createdAtMs': 0,
      });
      when(() => mockLanServer.receiveOnce(
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => encrypted);

      await pumpAndOpen(tester, validPayload());

      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepository.addEntry(
            site: any(named: 'site'),
            url: any(named: 'url'),
            username: any(named: 'username'),
            password: any(named: 'password'),
            notes: any(named: 'notes'),
            passkey: any(named: 'passkey'),
          ));
      verifyNever(() => mockPublishService.publish(any()));
      expect(find.text('Home'), findsOneWidget);
    });
  });
}

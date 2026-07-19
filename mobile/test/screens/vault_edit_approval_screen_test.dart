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
import 'package:truthid_mobile/services/vault_publish_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockRemoteSignerLanServer extends Mock
    implements RemoteSignerLanServer {}

class MockVaultRepository extends Mock implements VaultRepository {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockBlockchainService extends Mock implements BlockchainService {}

class MockVaultPublishService extends Mock implements VaultPublishService {}

void main() {
  late MockRemoteSignerLanServer mockLanServer;
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
  });

  setUp(() {
    mockLanServer = MockRemoteSignerLanServer();
    mockRepository = MockVaultRepository();
    mockStorage = MockLocalStorageService();
    mockBlockchain = MockBlockchainService();
    mockPublishService = MockVaultPublishService();

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
        providersOk: ['local-kubo'],
        providersFailed: [],
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

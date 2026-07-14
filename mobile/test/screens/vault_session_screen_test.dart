import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_session_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/ecies_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/pinning_provider_service.dart';
import 'package:truthid_mobile/services/vault_lan_server_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';
import 'package:truthid_mobile/services/vault_sync_service.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockVaultSyncService extends Mock implements VaultSyncService {}

class MockEciesService extends Mock implements EciesService {}

class MockVaultLanServerService extends Mock
    implements VaultLanServerService {}

class MockPinningProviderService extends Mock
    implements PinningProviderService {}

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockDeviceKeyService mockKeyService;
  late MockVaultSyncService mockSyncService;
  late MockEciesService mockEcies;
  late MockVaultLanServerService mockLanServer;
  late MockPinningProviderService mockPinningProviderService;

  const deviceAddress = '0x1234567890123456789012345678901234567890';
  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey =
      '0x02${'ab' * 32}'; // 33 bytes comprimida, formato-only (nunca de fato parseada nos testes com EciesService mockado)

  Map<String, dynamic> validPayload({
    String sessionId = 'session-abc',
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
  }) =>
      {
        'action': 'truthid-vault-session',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
      };

  setUpAll(() {
    registerFallbackValue(BigInt.one);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockKeyService = MockDeviceKeyService();
    mockSyncService = MockVaultSyncService();
    mockEcies = MockEciesService();
    mockLanServer = MockVaultLanServerService();
    mockPinningProviderService = MockPinningProviderService();

    // Sem provider Kubo configurado por padrão — o dead-drop (13.9, fatia
    // 2a) fica no early-return silencioso do IpfsPinClient.publishDeadDrop
    // sem nenhuma chamada de rede, então os testes de LAN abaixo não
    // precisam mockar IpfsPinClient também.
    when(() => mockPinningProviderService.load()).thenAnswer((_) async => []);

    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => deviceAddress);
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );
    when(() => mockEcies.encrypt(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: VaultSessionScreen(
        payload: payload,
        blockchainService: mockBlockchain,
        localStorageService: mockStorage,
        deviceKeyService: mockKeyService,
        vaultSyncService: mockSyncService,
        eciesService: mockEcies,
        lanServerService: mockLanServer,
        pinningProviderService: mockPinningProviderService,
      ),
    );
  }

  VaultEntry buildEntry(String site, List<String> profiles) => VaultEntry(
        id: 'id-$site',
        site: site,
        url: '',
        username: 'u',
        password: 'p',
        notes: '',
        profiles: profiles,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  Future<void> goToMatchesUI(WidgetTester tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(
          status: VaultSyncStatus.synced,
          entries: [
            buildEntry('github.com', ['Trabalho']),
            buildEntry('netflix.com', ['Casa']),
            buildEntry('slack.com', ['Trabalho']),
          ],
          profileNames: const ['Trabalho', 'Casa'],
        ));

    await tester.pumpWidget(buildScreen(validPayload()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trabalho'));
    await tester.pumpAndSettle();
  }

  group('validação do schema v1 do QR', () {
    testWidgets('payload sem sessionId mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(sessionId: '')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload sem ephemeralPubKey mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(ephemeralPubKey: '')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload com schema version desconhecida mostra erro',
        (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(v: 2)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('QR expirado mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(
        validPayload(expiresAt: DateTime.now().subtract(const Duration(minutes: 1))),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('payload válido mostra o sessionId', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.text('session-abc'), findsOneWidget);
    });
  });

  testWidgets('escolher perfil mostra a contagem correta de entradas',
      (tester) async {
    await goToMatchesUI(tester);

    expect(find.text('2'), findsOneWidget); // github.com + slack.com
    expect(find.text('Send to extension'), findsOneWidget);
  });

  group('envio via LAN', () {
    testWidgets('sucesso: cifra, serve e mostra "Sent"', (tester) async {
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);

      await goToMatchesUI(tester);
      await tester.tap(find.text('Send to extension'));
      await tester.pumpAndSettle();

      expect(find.text('Sent'), findsOneWidget);
      verify(() => mockEcies.encrypt(any(), validEphemeralPubKey)).called(1);
    });

    testWidgets('timeout: ninguém conectou, mostra "Nothing arrived" com Try again',
        (tester) async {
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => false);

      await goToMatchesUI(tester);
      await tester.tap(find.text('Send to extension'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing arrived'), findsOneWidget);

      // "Try again" reenvia sem precisar escanear de novo.
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer((_) async => true);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('erro: exceção durante o envio mostra tela de erro',
        (tester) async {
      when(() => mockLanServer.serveOnce(
            encryptedBlob: any(named: 'encryptedBlob'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenThrow(StateError('no available port'));

      await goToMatchesUI(tester);
      await tester.tap(find.text('Send to extension'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to send'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_session_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';
import 'package:truthid_mobile/services/vault_sync_service.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

class MockVaultSyncService extends Mock implements VaultSyncService {}

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockDeviceKeyService mockKeyService;
  late MockVaultSyncService mockSyncService;

  const deviceAddress = '0x1234567890123456789012345678901234567890';

  setUpAll(() {
    registerFallbackValue(BigInt.one);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockKeyService = MockDeviceKeyService();
    mockSyncService = MockVaultSyncService();

    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => deviceAddress);
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: VaultSessionScreen(
        payload: payload,
        blockchainService: mockBlockchain,
        localStorageService: mockStorage,
        deviceKeyService: mockKeyService,
        vaultSyncService: mockSyncService,
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

  testWidgets('payload sem sessionId mostra erro', (tester) async {
    await tester.pumpWidget(buildScreen({'action': 'truthid-vault-session'}));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid QR'), findsOneWidget);
  });

  testWidgets('payload válido mostra o sessionId', (tester) async {
    await tester.pumpWidget(buildScreen({
      'action': 'truthid-vault-session',
      'sessionId': 'session-abc',
    }));
    await tester.pumpAndSettle();

    expect(find.text('session-abc'), findsOneWidget);
  });

  testWidgets(
      'escolher perfil mostra a contagem correta e sempre termina em "not available"',
      (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(status: VaultSyncStatus.synced, entries: [
          buildEntry('github.com', ['Trabalho']),
          buildEntry('netflix.com', ['Casa']),
          buildEntry('slack.com', ['Trabalho']),
        ]));

    await tester.pumpWidget(buildScreen({
      'action': 'truthid-vault-session',
      'sessionId': 'session-abc',
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Trabalho'), findsOneWidget);
    await tester.tap(find.text('Trabalho'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget); // github.com + slack.com

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.textContaining('Nothing was sent'), findsOneWidget);
  });
}

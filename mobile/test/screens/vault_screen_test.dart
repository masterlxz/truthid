import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_entry_detail_screen.dart';
import 'package:truthid_mobile/screens/vault_screen.dart';
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
    when(() => mockStorage.savePairedIdentity(any())).thenAnswer((_) async {});
    when(() => mockStorage.clearPairedIdentity()).thenAnswer((_) async {});
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );
  });

  Widget buildScreen() {
    return MaterialApp(
      home: Scaffold(
        body: VaultScreen(
          blockchainService: mockBlockchain,
          localStorageService: mockStorage,
          deviceKeyService: mockKeyService,
          vaultSyncService: mockSyncService,
        ),
      ),
    );
  }

  VaultEntry buildEntry(String site, {List<String> profiles = const []}) =>
      VaultEntry(
        id: 'id-$site',
        site: site,
        url: '',
        username: 'user-$site',
        password: 'supersecretpassword',
        notes: '',
        profiles: profiles,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  testWidgets('device não pareado mostra estado "not paired"', (tester) async {
    when(() => mockStorage.getPairedIdentityId())
        .thenAnswer((_) async => null);
    when(() => mockBlockchain.getDevice(deviceAddress))
        .thenAnswer((_) async => null);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Device not paired'), findsOneWidget);
  });

  testWidgets('noVaultPublished mostra o texto certo', (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        const VaultSyncOutcome(
            status: VaultSyncStatus.noVaultPublished, entries: []));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('No vault published yet'), findsOneWidget);
  });

  testWidgets('noVaultKey mostra o texto certo', (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        const VaultSyncOutcome(
            status: VaultSyncStatus.noVaultKey, entries: []));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Vault key not available'), findsOneWidget);
  });

  testWidgets('syncFailedNoCache mostra o banner de erro', (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(
            status: VaultSyncStatus.syncFailedNoCache,
            entries: const [],
            error: 'network down'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Could not load your vault'), findsOneWidget);
  });

  testWidgets('synced renderiza entradas com senha sempre mascarada',
      (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(
            status: VaultSyncStatus.synced,
            entries: [buildEntry('example.com')]));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('supersecretpassword'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
  });

  testWidgets('offlineUsingCache mostra o banner informativo',
      (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(
            status: VaultSyncStatus.offlineUsingCache,
            entries: [buildEntry('example.com')],
            error: 'network down'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('busca filtra por site/username/perfil', (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(status: VaultSyncStatus.synced, entries: [
          buildEntry('github.com', profiles: ['Trabalho']),
          buildEntry('netflix.com', profiles: ['Casa']),
        ]));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('netflix.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'trabalho');
    await tester.pumpAndSettle();

    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('netflix.com'), findsNothing);
  });

  testWidgets('tap na entrada navega pro detail', (tester) async {
    when(() => mockSyncService.sync(any())).thenAnswer((_) async =>
        VaultSyncOutcome(
            status: VaultSyncStatus.synced,
            entries: [buildEntry('example.com')]));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('example.com'));
    await tester.pumpAndSettle();

    expect(find.byType(VaultEntryDetailScreen), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_device_permissions_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Mesma razão de vault_profiles_screen_test.dart: VaultRepository faz I/O
// real de arquivo, que nunca resolve dentro da zona FakeAsync de um widget
// test — sempre mockado nos testes de tela.
class MockVaultRepository extends Mock implements VaultRepository {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  late MockVaultRepository repo;
  late MockBlockchainService blockchain;

  const deviceA = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const revokedDevice = '0xccccccccccccccccccccccccccccccccccccccc';

  setUp(() {
    repo = MockVaultRepository();
    blockchain = MockBlockchainService();
  });

  Widget buildScreen() => MaterialApp(
        home: VaultDevicePermissionsScreen(
          identityId: '1',
          repository: repo,
          blockchainService: blockchain,
        ),
      );

  testWidgets('mostra "nenhum device" quando a identidade não tem devices',
      (tester) async {
    when(() => blockchain.getDevicesForIdentity(BigInt.one))
        .thenAnswer((_) async => []);
    when(() => repo.listDevicePermissions()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('No active devices registered.'), findsOneWidget);
  });

  testWidgets('lista devices ativos, filtra os revogados', (tester) async {
    when(() => blockchain.getDevicesForIdentity(BigInt.one))
        .thenAnswer((_) async => [deviceA, revokedDevice]);
    when(() => blockchain.getDevice(deviceA)).thenAnswer(
      (_) async => DeviceInfo(
        identityId: BigInt.one,
        revoked: false,
        exists: true,
        pubKey: deviceA,
        label: 'Galaxy Z Flip',
      ),
    );
    when(() => blockchain.getDevice(revokedDevice)).thenAnswer(
      (_) async => DeviceInfo(
        identityId: BigInt.one,
        revoked: true,
        exists: true,
        pubKey: revokedDevice,
        label: 'Old phone',
      ),
    );
    when(() => repo.listDevicePermissions()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Galaxy Z Flip'), findsOneWidget);
    expect(find.text('Old phone'), findsNothing);
    expect(find.text('Read only'), findsOneWidget);
  });

  testWidgets('device já autorizado mostra "Can write"', (tester) async {
    when(() => blockchain.getDevicesForIdentity(BigInt.one))
        .thenAnswer((_) async => [deviceA]);
    when(() => blockchain.getDevice(deviceA)).thenAnswer(
      (_) async => DeviceInfo(
        identityId: BigInt.one,
        revoked: false,
        exists: true,
        pubKey: deviceA,
        label: 'Galaxy Z Flip',
      ),
    );
    when(() => repo.listDevicePermissions()).thenAnswer(
      (_) async => [const VaultDevicePermission(pubKey: deviceA, canWrite: true)],
    );

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('✓ Can write'), findsOneWidget);
  });

  testWidgets('tocar no toggle chama setDevicePermission e recarrega',
      (tester) async {
    when(() => blockchain.getDevicesForIdentity(BigInt.one))
        .thenAnswer((_) async => [deviceA]);
    when(() => blockchain.getDevice(deviceA)).thenAnswer(
      (_) async => DeviceInfo(
        identityId: BigInt.one,
        revoked: false,
        exists: true,
        pubKey: deviceA,
        label: 'Galaxy Z Flip',
      ),
    );
    when(() => repo.listDevicePermissions()).thenAnswer((_) async => []);
    when(() => repo.setDevicePermission(deviceA, true))
        .thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    when(() => repo.listDevicePermissions()).thenAnswer(
      (_) async => [const VaultDevicePermission(pubKey: deviceA, canWrite: true)],
    );

    await tester.tap(find.text('Read only'));
    await tester.pumpAndSettle();

    verify(() => repo.setDevicePermission(deviceA, true)).called(1);
    expect(find.text('✓ Can write'), findsOneWidget);
  });

  testWidgets('erro ao carregar devices aparece na tela', (tester) async {
    when(() => blockchain.getDevicesForIdentity(BigInt.one))
        .thenThrow(Exception('RPC unreachable'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('RPC unreachable'), findsOneWidget);
  });
}

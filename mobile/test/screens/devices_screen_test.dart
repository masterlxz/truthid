import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/devices_screen.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/device_key_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';

import '../utils/l10n_test_app.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockDeviceKeyService extends Mock implements DeviceKeyService {}

void main() {
  late MockBlockchainService mockBlockchain;
  late MockLocalStorageService mockStorage;
  late MockDeviceKeyService mockKeyService;

  final deviceAddress = '0x1234567890123456789012345678901234567890';

  setUpAll(() {
    registerFallbackValue(BigInt.zero);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    mockStorage = MockLocalStorageService();
    mockKeyService = MockDeviceKeyService();

    when(() => mockKeyService.getDeviceAddress())
        .thenAnswer((_) async => deviceAddress);
  });

  Widget buildScreen() {
    return wrapForTest(
      Scaffold(
        body: DevicesScreen(
          blockchainService: mockBlockchain,
          localStorageService: mockStorage,
          deviceKeyService: mockKeyService,
        ),
      ),
    );
  }

  testWidgets(
      'identityId e username já cacheados — mostra @username sem chamar '
      'getUsernameForIdentity', (tester) async {
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Aparece 2x na tela: no chip do cabeçalho e na seção "Identity".
    expect(find.text('@alice'), findsNWidgets(2));
    verifyNever(() => mockBlockchain.getUsernameForIdentity(any()));
  });

  testWidgets(
      'M8 (achado do /code-review high): identityId já cacheado mas '
      'username nunca resolveu — tenta de novo via resolvePairedUsername e '
      'mostra @username depois de resolver on-chain', (tester) async {
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockStorage.savePairedUsername('alice'))
        .thenAnswer((_) async {});
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: false, exists: true),
    );
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) async => 'alice');

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Aparece 2x na tela: no chip do cabeçalho e na seção "Identity".
    expect(find.text('@alice'), findsNWidgets(2));
    verify(() => mockBlockchain.getUsernameForIdentity(BigInt.one)).called(1);
    verify(() => mockStorage.savePairedUsername('alice')).called(1);
  });

  testWidgets(
      'auto-descoberta: device existe on-chain mas identityId ainda não '
      'estava salvo localmente — salva o identityId e resolve o username',
      (tester) async {
    when(() => mockStorage.getPairedIdentityId())
        .thenAnswer((_) async => null);
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockStorage.savePairedIdentity('7')).thenAnswer((_) async {});
    when(() => mockStorage.savePairedUsername('bob')).thenAnswer((_) async {});
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async => DeviceInfo(
          identityId: BigInt.from(7), revoked: false, exists: true),
    );
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.from(7)))
        .thenAnswer((_) async => 'bob');

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('@bob'), findsNWidgets(2));
    verify(() => mockStorage.savePairedIdentity('7')).called(1);
  });

  testWidgets(
      'device revogado com identidade previamente pareada — limpa o '
      'storage e mostra "Not registered"', (tester) async {
    when(() => mockStorage.getPairedIdentityId()).thenAnswer((_) async => '1');
    when(() => mockStorage.getPairedUsername())
        .thenAnswer((_) async => 'alice');
    when(() => mockStorage.clearPairedIdentity()).thenAnswer((_) async {});
    when(() => mockBlockchain.getDevice(deviceAddress)).thenAnswer(
      (_) async =>
          DeviceInfo(identityId: BigInt.one, revoked: true, exists: true),
    );

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Not registered'), findsOneWidget);
    verify(() => mockStorage.clearPairedIdentity()).called(1);
    verifyNever(() => mockBlockchain.getUsernameForIdentity(any()));
  });
}

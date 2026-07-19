import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/security_screen.dart';
import 'package:truthid_mobile/services/app_lock_service.dart';

class MockAppLockService extends Mock implements AppLockService {}

void main() {
  late MockAppLockService mockService;

  Widget buildScreen() =>
      MaterialApp(home: SecurityScreen(lockService: mockService));

  setUp(() {
    mockService = MockAppLockService();
  });

  testWidgets('mostra o switch desligado quando app lock não está habilitado',
      (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => false);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => true);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isFalse);
  });

  testWidgets('mostra o switch ligado quando app lock já está habilitado',
      (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => true);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => true);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });

  testWidgets('device sem suporte mostra aviso e desabilita o switch',
      (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => false);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => false);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('No biometrics'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('ligar chama authenticate antes de persistir, sucesso habilita',
      (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => false);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => true);
    when(() => mockService.authenticate()).thenAnswer((_) async => true);
    when(() => mockService.setEnabled(true)).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    verify(() => mockService.authenticate()).called(1);
    verify(() => mockService.setEnabled(true)).called(1);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });

  testWidgets(
      'ligar com authenticate falhando não persiste e mostra erro',
      (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => false);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => true);
    when(() => mockService.authenticate()).thenAnswer((_) async => false);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    verify(() => mockService.authenticate()).called(1);
    verifyNever(() => mockService.setEnabled(any()));
    expect(find.textContaining('Authentication failed'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isFalse);
  });

  testWidgets('desligar não chama authenticate', (tester) async {
    when(() => mockService.isEnabled()).thenAnswer((_) async => true);
    when(() => mockService.isDeviceSupported()).thenAnswer((_) async => true);
    when(() => mockService.setEnabled(false)).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.authenticate());
    verify(() => mockService.setEnabled(false)).called(1);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isFalse);
  });
}

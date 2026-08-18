import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/main.dart';
import 'package:truthid_mobile/services/app_lock_service.dart';

import '../utils/l10n_test_app.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late MockLocalAuthentication mockAuth;

  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions());
  });

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    mockAuth = MockLocalAuthentication();
  });

  tearDown(() {
    // Não vazar estado entre arquivos de teste — outros testes (ex.
    // deep_link_router_test.dart) assumem o default fail-safe `true`.
    AppLockService.isLockedNotifier.value = true;
    AppLockService.requestAuthentication = null;
  });

  testWidgets(
      'bloqueio habilitado: isLockedNotifier fica true e overlay aparece '
      'até autenticar', (tester) async {
    when(() => mockStorage.read(key: 'app_lock_enabled'))
        .thenAnswer((_) async => 'true');
    final authCompleter = Completer<bool>();
    when(() => mockAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        )).thenAnswer((_) => authCompleter.future);

    final service = AppLockService(storage: mockStorage, localAuth: mockAuth);
    await tester.pumpWidget(wrapForTest(AppLockGate(lockService: service)));
    await tester.pump();

    expect(AppLockService.isLockedNotifier.value, isTrue);
    expect(find.text('TruthID is locked'), findsOneWidget);

    authCompleter.complete(true);
    await tester.pump();
    await tester.pump();

    expect(AppLockService.isLockedNotifier.value, isFalse);
    expect(find.text('TruthID is locked'), findsNothing);
  });

  testWidgets(
      'bloqueio desabilitado: isLockedNotifier vira false sem precisar '
      'autenticar', (tester) async {
    when(() => mockStorage.read(key: 'app_lock_enabled'))
        .thenAnswer((_) async => null);

    final service = AppLockService(storage: mockStorage, localAuth: mockAuth);
    await tester.pumpWidget(wrapForTest(AppLockGate(lockService: service)));
    await tester.pump();

    expect(AppLockService.isLockedNotifier.value, isFalse);
    expect(find.text('TruthID is locked'), findsNothing);
    verifyNever(() => mockAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ));
  });

  testWidgets('initState liga requestAuthentication, dispose limpa',
      (tester) async {
    when(() => mockStorage.read(key: 'app_lock_enabled'))
        .thenAnswer((_) async => null);

    final service = AppLockService(storage: mockStorage, localAuth: mockAuth);
    await tester.pumpWidget(wrapForTest(AppLockGate(lockService: service)));
    await tester.pump();

    expect(AppLockService.requestAuthentication, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(AppLockService.requestAuthentication, isNull);
  });
}

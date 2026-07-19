import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/services/app_lock_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late MockLocalAuthentication mockAuth;
  late AppLockService service;

  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions());
  });

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    mockAuth = MockLocalAuthentication();
    service = AppLockService(storage: mockStorage, localAuth: mockAuth);
  });

  group('isEnabled/setEnabled', () {
    test('isEnabled retorna false quando nada foi persistido ainda', () async {
      when(() => mockStorage.read(key: 'app_lock_enabled'))
          .thenAnswer((_) async => null);

      expect(await service.isEnabled(), isFalse);
    });

    test('setEnabled(true) seguido de isEnabled faz round-trip', () async {
      String? written;
      when(() => mockStorage.write(
            key: 'app_lock_enabled',
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        written = invocation.namedArguments[#value] as String;
      });
      when(() => mockStorage.read(key: 'app_lock_enabled'))
          .thenAnswer((_) async => written);

      await service.setEnabled(true);
      expect(await service.isEnabled(), isTrue);
    });

    test('setEnabled(false) seguido de isEnabled faz round-trip', () async {
      String? written;
      when(() => mockStorage.write(
            key: 'app_lock_enabled',
            value: any(named: 'value'),
          )).thenAnswer((invocation) async {
        written = invocation.namedArguments[#value] as String;
      });
      when(() => mockStorage.read(key: 'app_lock_enabled'))
          .thenAnswer((_) async => written);

      await service.setEnabled(true);
      await service.setEnabled(false);
      expect(await service.isEnabled(), isFalse);
    });
  });

  group('isDeviceSupported/authenticate — delega pro LocalAuthentication', () {
    test('isDeviceSupported repassa o resultado do LocalAuthentication', () async {
      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => true);
      expect(await service.isDeviceSupported(), isTrue);

      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => false);
      expect(await service.isDeviceSupported(), isFalse);
    });

    test('authenticate chama LocalAuthentication com biometricOnly false',
        () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);

      final result = await service.authenticate();

      expect(result, isTrue);
      final captured = verify(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: captureAny(named: 'options'),
          )).captured;
      final options = captured.single as AuthenticationOptions;
      expect(options.biometricOnly, isFalse);
    });

    test('authenticate repassa false quando o usuário cancela/falha', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => false);

      expect(await service.authenticate(), isFalse);
    });
  });
}

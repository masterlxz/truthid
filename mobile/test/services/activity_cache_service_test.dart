import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/models/smart_account_activity.dart';
import 'package:truthid_mobile/services/activity_cache_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late ActivityCacheService cacheService;

  final identityId = BigInt.one;
  final activity = SmartAccountActivity(
    type: SmartAccountActivityType.sessionCreated,
    hash: '0xTx1',
    blockNumber: 100,
    logIndex: 0,
    timestamp: 1751000000,
    costWei: BigInt.from(21000000000000),
  );

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    cacheService = ActivityCacheService(storage: mockStorage);

    when(() => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
  });

  test('write seguido de read faz round-trip corretamente', () async {
    String? written;
    when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((invocation) async {
      written = invocation.namedArguments[#value] as String;
    });
    when(() => mockStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => written);

    await cacheService.write(identityId, lastScannedBlock: 12345, activities: [activity]);
    final cached = await cacheService.read(identityId);

    expect(cached, isNotNull);
    expect(cached!.lastScannedBlock, 12345);
    expect(cached.activities, hasLength(1));
    expect(cached.activities.single.hash, '0xTx1');
    expect(cached.activities.single.costWei, BigInt.from(21000000000000));
  });

  test('JSON corrompido faz read devolver null', () async {
    when(() => mockStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'not valid json {{{');

    final cached = await cacheService.read(identityId);

    expect(cached, isNull);
  });

  test('read sem cache existente devolve null', () async {
    when(() => mockStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);

    final cached = await cacheService.read(identityId);

    expect(cached, isNull);
  });

  test('clear remove a chave do storage', () async {
    when(() => mockStorage.delete(key: any(named: 'key'))).thenAnswer((_) async {});

    await cacheService.clear(identityId);

    verify(() => mockStorage.delete(key: 'activity_cache_$identityId')).called(1);
  });

  test('falha de escrita é engolida silenciosamente', () async {
    when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenThrow(Exception('storage full'));

    await expectLater(
      cacheService.write(identityId, lastScannedBlock: 1, activities: []),
      completes,
    );
  });
}

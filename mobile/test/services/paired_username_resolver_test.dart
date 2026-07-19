import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/paired_username_resolver.dart';

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  late MockLocalStorageService mockStorage;
  late MockBlockchainService mockBlockchain;

  setUpAll(() {
    registerFallbackValue(BigInt.zero);
  });

  setUp(() {
    mockStorage = MockLocalStorageService();
    mockBlockchain = MockBlockchainService();
  });

  test('username já em cache: devolve sem consultar a chain', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => 'alice');

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, 'alice');
    verifyNever(() => mockBlockchain.getUsernameForIdentity(any()));
  });

  test('username null: resolve on-chain e persiste', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) async => 'alice');
    when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, 'alice');
    verify(() => mockStorage.savePairedUsername('alice')).called(1);
  });

  test('resolução on-chain devolve null: não persiste nada', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) async => null);

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, isNull);
    verifyNever(() => mockStorage.savePairedUsername(any()));
  });

  test('falha transiente de RPC: devolve null em vez de propagar', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenThrow(Exception('log scan timed out'));

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, isNull);
    verifyNever(() => mockStorage.savePairedUsername(any()));
  });
}

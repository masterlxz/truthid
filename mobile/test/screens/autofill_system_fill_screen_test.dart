import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/autofill_system_fill_screen.dart';
import 'package:truthid_mobile/services/autofill_bridge_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockAutofillBridgeService extends Mock implements AutofillBridgeService {}

void main() {
  late MockVaultRepository mockRepository;
  late MockAutofillBridgeService mockBridge;

  VaultEntry credential() => VaultEntry(
        id: 'cred1',
        site: 'github.com',
        url: '',
        username: 'alice',
        password: 'hunter2',
        notes: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  setUpAll(() {
    registerFallbackValue(<String, String>{});
  });

  setUp(() {
    mockRepository = MockVaultRepository();
    mockBridge = MockAutofillBridgeService();
    when(() => mockBridge.submitResult(any())).thenAnswer((_) async {});
    when(() => mockBridge.cancel()).thenAnswer((_) async {});
  });

  Widget buildScreen(String entryType) {
    return MaterialApp(
      home: AutofillSystemFillScreen(
        entryType: entryType,
        requestingPackage: 'com.example.app',
        repository: mockRepository,
        bridge: mockBridge,
      ),
    );
  }

  VaultEntry addressEntry() => VaultEntry(
        id: 'addr1',
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.address,
        address: const AddressData(
          label: 'Home',
          fullName: 'Alice Example',
          street: 'Main St',
          number: '123',
          neighborhood: 'Downtown',
          city: 'Springfield',
          state: 'IL',
          zipCode: '00000-000',
          country: 'US',
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  VaultEntry cardEntry() => VaultEntry(
        id: 'card1',
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.creditCard,
        creditCard: const CreditCardData(
          label: 'Nubank',
          cardHolderName: 'Alice Example',
          cardNumber: '4111111111111234',
          expiryMonth: '09',
          expiryYear: '2029',
          cvv: '123',
          cardNetwork: CardNetwork.visa,
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  group('credencial', () {
    testWidgets('mostra só entradas do tipo credential', (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer(
        (_) async => [credential(), addressEntry()],
      );

      await tester.pumpWidget(buildScreen('credential'));
      await tester.pumpAndSettle();

      expect(find.text('github.com'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('tocar na entrada submete username/email/password pro bridge',
        (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => [credential()]);

      await tester.pumpWidget(buildScreen('credential'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('github.com'));
      await tester.pump();

      verify(() => mockBridge.submitResult({
            'USERNAME': 'alice',
            'EMAIL': 'alice',
            'PASSWORD': 'hunter2',
          })).called(1);
    });
  });

  group('endereço', () {
    testWidgets('mostra só entradas do tipo address', (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer(
        (_) async => [credential(), addressEntry()],
      );

      await tester.pumpWidget(buildScreen('address'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('github.com'), findsNothing);
    });

    testWidgets('tocar na entrada submete os campos de endereço mapeados',
        (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => [addressEntry()]);

      await tester.pumpWidget(buildScreen('address'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pump();

      verify(() => mockBridge.submitResult({
            'FULL_NAME': 'Alice Example',
            'STREET_ADDRESS': 'Main St, 123',
            'POSTAL_CODE': '00000-000',
            'LOCALITY': 'Springfield',
            'REGION': 'IL',
            'COUNTRY': 'US',
          })).called(1);
    });
  });

  group('cartão de crédito', () {
    testWidgets('mostra só entradas do tipo creditCard', (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer(
        (_) async => [credential(), cardEntry()],
      );

      await tester.pumpWidget(buildScreen('creditCard'));
      await tester.pumpAndSettle();

      expect(find.text('Nubank'), findsOneWidget);
      expect(find.text('github.com'), findsNothing);
    });

    testWidgets(
        'tocar na entrada submete número/validade/CVV, incluindo o campo combinado MM/AA',
        (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => [cardEntry()]);

      await tester.pumpWidget(buildScreen('creditCard'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pump();

      verify(() => mockBridge.submitResult({
            'CARD_NUMBER': '4111111111111234',
            'CARD_EXPIRATION_MONTH': '09',
            'CARD_EXPIRATION_YEAR': '2029',
            'CARD_EXPIRATION_DATE': '09/29',
            'CARD_SECURITY_CODE': '123',
          })).called(1);
    });
  });

  group('vault vazio', () {
    testWidgets('mostra mensagem de vazio e botão de fechar', (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildScreen('address'));
      await tester.pumpAndSettle();

      expect(find.textContaining("don't have any saved addresses"), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      verify(() => mockBridge.cancel()).called(1);
    });
  });

  group('cancelar', () {
    testWidgets('botão Cancel chama bridge.cancel()', (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => [credential()]);

      await tester.pumpWidget(buildScreen('credential'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verify(() => mockBridge.cancel()).called(1);
    });
  });
}

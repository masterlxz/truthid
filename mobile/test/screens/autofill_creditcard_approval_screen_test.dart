import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/autofill_creditcard_approval_screen.dart';
import 'package:truthid_mobile/services/result_delivery_channel.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

class MockResultDeliveryChannel extends Mock
    implements ResultDeliveryChannel {}

void main() {
  late MockVaultRepository mockRepository;
  late MockResultDeliveryChannel mockDelivery;

  final farFuture = DateTime.now().add(const Duration(minutes: 3));
  final validEphemeralPubKey = '0x02${'ab' * 32}';

  const card1 = CreditCardData(
    label: 'Nubank',
    cardHolderName: 'Alice Example',
    cardNumber: '4111111111111234',
    expiryMonth: '09',
    expiryYear: '2029',
    cvv: '123',
    cardNetwork: CardNetwork.visa,
  );
  const card2 = CreditCardData(
    label: 'Itau Platinum',
    cardHolderName: 'Alice Example',
    cardNumber: '5500000000005678',
    expiryMonth: '11',
    expiryYear: '2027',
    cvv: '456',
    cardNetwork: CardNetwork.mastercard,
  );

  VaultEntry cardEntry(CreditCardData card) => VaultEntry(
        id: card.label,
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.creditCard,
        creditCard: card,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  Map<String, dynamic> validPayload({
    String sessionId = 'session-abc',
    String? ephemeralPubKey,
    DateTime? expiresAt,
    int v = 1,
    String appName = 'checkout.example.com',
  }) =>
      {
        'action': 'truthid-autofill-creditcard',
        'v': v,
        'sessionId': sessionId,
        'ephemeralPubKey': ephemeralPubKey ?? validEphemeralPubKey,
        'expiresAt': (expiresAt ?? farFuture).millisecondsSinceEpoch,
        'appName': appName,
      };

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    mockRepository = MockVaultRepository();
    mockDelivery = MockResultDeliveryChannel();
  });

  Widget buildScreen(Map<String, dynamic> payload) {
    return MaterialApp(
      home: AutofillCreditCardApprovalScreen(
        payload: payload,
        repository: mockRepository,
        deliveryChannel: mockDelivery,
      ),
    );
  }

  group('validação do schema v1 do QR', () {
    testWidgets('payload sem sessionId mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(sessionId: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('payload sem ephemeralPubKey mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(ephemeralPubKey: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('schema version desconhecida mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(v: 2)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });

    testWidgets('QR expirado mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(
        validPayload(
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('payload sem appName mostra erro', (tester) async {
      await tester.pumpWidget(buildScreen(validPayload(appName: '')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid QR'), findsOneWidget);
    });
  });

  group('vault sem cartões', () {
    testWidgets('entrega {status: no-cards} direto, sem mostrar picker',
        (tester) async {
      when(() => mockRepository.listEntries()).thenAnswer((_) async => []);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {'status': 'no-cards'},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });
  });

  group('picker de cartões', () {
    testWidgets('mostra as entradas de tipo creditCard, ignora outras',
        (tester) async {
      final credential = VaultEntry(
        id: 'cred',
        site: 'github.com',
        url: '',
        username: 'alice',
        password: 'x',
        notes: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      when(() => mockRepository.listEntries()).thenAnswer(
          (_) async => [credential, cardEntry(card1), cardEntry(card2)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.text('Nubank'), findsOneWidget);
      expect(find.text('Itau Platinum'), findsOneWidget);
      expect(find.text('github.com'), findsNothing);
    });

    testWidgets('picker mostra número mascarado, nunca o número completo',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.textContaining('1234'), findsOneWidget);
      expect(find.textContaining(card1.cardNumber), findsNothing);
    });

    testWidgets('tocar numa entrada mostra a confirmação com os detalhes',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pumpAndSettle();

      expect(find.textContaining('wants to fill a form'), findsOneWidget);
      expect(find.text('Alice Example'), findsOneWidget);
      expect(find.text('09/2029'), findsOneWidget);
    });

    testWidgets(
        'card number e CVV começam mascarados na confirmação, revelam ao tocar o olho',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pumpAndSettle();

      expect(find.text(card1.cardNumber), findsNothing);
      expect(find.text(card1.cvv), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pumpAndSettle();

      expect(find.text(card1.cardNumber), findsOneWidget);
    });

    testWidgets(
        'máscara é de tamanho fixo, não vaza o comprimento do número/CVV '
        '(achado da 15.8: `\'•\' * value.length` distinguia CVV de 3 x 4 '
        'dígitos, ou PAN Amex de 15 x Visa/Master de 16)', (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pumpAndSettle();

      // Mesma máscara fixa que _CopyableRow (vault_entry_detail_screen.dart)
      // já usa — não '•' * value.length, que vazaria o comprimento real.
      expect(find.text('••••••••'), findsNWidgets(2)); // card number + cvv
    });

    testWidgets('Approve entrega o cartão escolhido', (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1), cardEntry(card2)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Itau Platinum'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {'status': 'filled', 'card': card2.toJson()},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('Reject a partir do picker recusa o pedido inteiro',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deny request'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {'status': 'rejected'},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
    });

    testWidgets('Reject a partir da confirmação também recusa o pedido inteiro',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {'status': 'rejected'},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
    });

    testWidgets('timeout mostra a tela de "nada chegou"', (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [cardEntry(card1)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.timeout),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nubank'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing arrived'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/autofill_address_approval_screen.dart';
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

  const address1 = AddressData(
    label: 'Home',
    fullName: 'Alice Example',
    street: 'Main St',
    number: '123',
    neighborhood: 'Downtown',
    city: 'Springfield',
    state: 'IL',
    zipCode: '00000-000',
    country: 'US',
  );
  const address2 = AddressData(
    label: 'Work',
    fullName: 'Alice Example',
    street: 'Market St',
    number: '456',
    neighborhood: 'Uptown',
    city: 'Springfield',
    state: 'IL',
    zipCode: '00000-111',
    country: 'US',
  );

  VaultEntry addressEntry(AddressData address) => VaultEntry(
        id: address.label,
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.address,
        address: address,
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
        'action': 'truthid-autofill-address',
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
      home: AutofillAddressApprovalScreen(
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

  group('vault sem endereços', () {
    testWidgets('entrega {status: no-addresses} direto, sem mostrar picker',
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
            result: {'status': 'no-addresses'},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });
  });

  group('picker de endereços', () {
    testWidgets('mostra as entradas de tipo address, ignora outras', (tester) async {
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
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [credential, addressEntry(address1), addressEntry(address2)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('github.com'), findsNothing);
    });

    testWidgets('tocar numa entrada mostra a confirmação com os detalhes',
        (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [addressEntry(address1)]);

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.textContaining('wants to fill a form'), findsOneWidget);
      expect(find.text('Alice Example'), findsOneWidget);
      expect(find.text('Springfield/IL'), findsOneWidget);
    });

    testWidgets('Approve entrega o endereço escolhido', (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [addressEntry(address1), addressEntry(address2)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockDelivery.deliver(
            result: {'status': 'filled', 'address': address2.toJson()},
            sessionId: 'session-abc',
            expiresAt: any(named: 'expiresAt'),
          )).called(1);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('Reject a partir do picker recusa o pedido inteiro', (tester) async {
      when(() => mockRepository.listEntries())
          .thenAnswer((_) async => [addressEntry(address1)]);
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
          .thenAnswer((_) async => [addressEntry(address1)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.sent),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
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
          .thenAnswer((_) async => [addressEntry(address1)]);
      when(() => mockDelivery.deliver(
            result: any(named: 'result'),
            sessionId: any(named: 'sessionId'),
            expiresAt: any(named: 'expiresAt'),
          )).thenAnswer(
        (_) async => const DeliveryResult(outcome: DeliveryOutcome.timeout),
      );

      await tester.pumpWidget(buildScreen(validPayload()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing arrived'), findsOneWidget);
    });
  });
}

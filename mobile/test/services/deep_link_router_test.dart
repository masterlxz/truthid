import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/app_lock_service.dart';
import 'package:truthid_mobile/services/deep_link_router.dart';

void main() {
  // Desbloqueado por padrão nos testes existentes, que não se importam com
  // o gate de app-lock (débito M1) — sem isso, o default fail-safe `true`
  // faria `handlePayload` esperar pra sempre por um desbloqueio que nunca
  // vem neste tree de teste (sem AppLockGate).
  setUp(() {
    AppLockService.isLockedNotifier.value = false;
    AppLockService.requestAuthentication = null;
  });

  tearDown(() {
    AppLockService.isLockedNotifier.value = true;
    AppLockService.requestAuthentication = null;
  });

  // `pumpAndSettle` nunca termina pra SignRequestApprovalScreen (usa
  // BlockchainService/LocalStorageService reais, não mockados — o spinner
  // de loading indeterminado nunca "assenta"). Um pump avulso já basta:
  // só precisamos confirmar QUAL tela foi empurrada (AppBar estático,
  // presente já no primeiro frame), não esperar o resultado da resolução.
  Future<void> pumpRouter(
    WidgetTester tester,
    Map<String, dynamic> payload,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => DeepLinkRouter.handlePayload(context, payload),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('truthid-sign-message empurra SignMessageApprovalScreen',
      (tester) async {
    await pumpRouter(tester, {
      'action': 'truthid-sign-message',
      'v': 1,
      'sessionId': 's1',
      'ephemeralPubKey': '0x02${'ab' * 32}',
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      'appName': 'Test App',
      'purpose': 'router-test',
    });

    expect(find.text('Sign message request'), findsOneWidget);
  });

  testWidgets('truthid-sign-request empurra SignRequestApprovalScreen',
      (tester) async {
    await pumpRouter(tester, {
      'action': 'truthid-sign-request',
      'v': 1,
      'sessionId': 's1',
      'ephemeralPubKey': '0x02${'ab' * 32}',
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      'appName': 'Test App',
      'dest': '0xcccccccccccccccccccccccccccccccccccccccc',
      'callData': '0xabcdef',
      'functionSignature': 'noop()',
    });

    expect(find.text('Sign & execute request'), findsOneWidget);
  });

  testWidgets(
      'truthid-autofill-address empurra AutofillAddressApprovalScreen',
      (tester) async {
    await pumpRouter(tester, {
      'action': 'truthid-autofill-address',
      'v': 1,
      'sessionId': 's1',
      'ephemeralPubKey': '0x02${'ab' * 32}',
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      'appName': 'Test App',
    });

    expect(find.text('Autofill request'), findsOneWidget);
  });

  testWidgets('action desconhecida mostra snackbar, não navega',
      (tester) async {
    await pumpRouter(tester, {'action': 'something-weird'});

    expect(find.textContaining('Unrecognized request'), findsOneWidget);
  });

  testWidgets('sem action mostra snackbar com "no action"', (tester) async {
    await pumpRouter(tester, {});

    expect(find.textContaining('no action'), findsOneWidget);
  });

  group('gate de app-lock (M1)', () {
    testWidgets('bloqueado: só navega depois de desbloquear', (tester) async {
      AppLockService.isLockedNotifier.value = true;

      await pumpRouter(tester, {
        'action': 'truthid-sign-message',
        'v': 1,
        'sessionId': 's-lock-1',
        'ephemeralPubKey': '0x02${'ab' * 32}',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 3))
            .millisecondsSinceEpoch,
        'appName': 'Test App',
        'purpose': 'router-test',
      });

      expect(find.text('Sign message request'), findsNothing);

      AppLockService.isLockedNotifier.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Sign message request'), findsOneWidget);
    });

    testWidgets('bloqueado: dispara autenticação proativamente', (tester) async {
      AppLockService.isLockedNotifier.value = true;
      var called = false;
      AppLockService.requestAuthentication = () => called = true;

      await pumpRouter(tester, {
        'action': 'truthid-sign-message',
        'v': 1,
        'sessionId': 's-lock-2',
        'ephemeralPubKey': '0x02${'ab' * 32}',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 3))
            .millisecondsSinceEpoch,
        'appName': 'Test App',
        'purpose': 'router-test',
      });

      expect(called, isTrue);
    });
  });
}

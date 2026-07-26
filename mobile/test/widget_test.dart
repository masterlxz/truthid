import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/main.dart';
import 'package:truthid_mobile/screens/devices_screen.dart';
import 'package:truthid_mobile/screens/sessions_screen.dart';
import 'package:truthid_mobile/screens/vault_screen.dart';
import 'package:truthid_mobile/screens/wallet_screen.dart';

void main() {
  testWidgets('App renders the root screen with all tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const TruthIDApp());

    expect(find.text('TruthID'), findsWidgets);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets(
      'M10 (achado do /code-review high): só a aba inicial (Devices) é '
      'construída no cold start — as outras 3 só constroem quando '
      'visitadas, evitando 4 getDevice() redundantes de uma vez',
      (tester) async {
    // Pumpa RootScreen direto (sem o AppLockGate por cima) — o overlay
    // opaco do AppLockGate enquanto ele resolve isEnabled() bloquearia o
    // tap abaixo, e esperar isso resolver (pumpAndSettle) trava a suíte
    // porque DevicesScreen já dispara chamadas de rede reais que nunca
    // completam em ambiente de teste sandboxed.
    await tester.pumpWidget(const MaterialApp(home: RootScreen()));

    expect(find.byType(DevicesScreen), findsOneWidget);
    expect(find.byType(SessionsScreen), findsNothing);
    expect(find.byType(WalletScreen), findsNothing);
    expect(find.byType(VaultScreen), findsNothing);

    await tester.tap(find.text('Sessions'));
    await tester.pump();

    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(WalletScreen), findsNothing);
    expect(find.byType(VaultScreen), findsNothing);
  });
}

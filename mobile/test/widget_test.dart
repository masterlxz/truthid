import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/main.dart';

void main() {
  testWidgets('App renders the root screen with both tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const TruthIDApp());

    expect(find.text('TruthID'), findsWidgets);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Sessões'), findsOneWidget);
  });
}

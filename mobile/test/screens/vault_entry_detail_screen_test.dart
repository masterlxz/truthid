import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/screens/vault_entry_detail_screen.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

void main() {
  final entry = VaultEntry(
    id: '1',
    site: 'example.com',
    url: 'https://example.com',
    username: 'alice',
    password: 'supersecret',
    notes: 'some notes',
    profiles: const ['Trabalho'],
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Widget buildScreen() =>
      MaterialApp(home: VaultEntryDetailScreen(entry: entry));

  testWidgets('senha escondida por padrão', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('supersecret'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
  });

  testWidgets('toggle revela a senha', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    expect(find.text('supersecret'), findsOneWidget);
    expect(find.text('••••••••'), findsNothing);
  });

  testWidgets('botão de copiar da senha mostra confirmação', (tester) async {
    await tester.pumpWidget(buildScreen());

    final copyButtons = find.byIcon(Icons.copy);
    expect(copyButtons, findsNWidgets(2)); // username + password

    await tester.tap(copyButtons.last); // linha da senha é a última
    await tester.pump();

    expect(find.text('Password copied!'), findsOneWidget);
  });

  testWidgets('mostra site, notas e perfis', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('example.com'), findsWidgets);
    expect(find.text('some notes'), findsOneWidget);
    expect(find.text('Trabalho'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_entry_detail_screen.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Repositório mockado, não real — VaultRepository faz I/O real de arquivo
// (dart:io), que nunca resolve dentro da zona FakeAsync de um widget test
// (achado da Sessão 98, validação manual dos testes escritos na Sessão 97:
// travava pumpAndSettle indefinidamente). O CRUD real do repositório já é
// coberto por vault_repository_test.dart (testes puros, sem widget).
class MockVaultRepository extends Mock implements VaultRepository {}

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

  Widget buildScreen({bool canWrite = false, VaultRepository? repository}) =>
      MaterialApp(
        home: VaultEntryDetailScreen(
          entry: entry,
          canWrite: canWrite,
          repository: repository,
        ),
      );

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

  group('canWrite = true', () {
    testWidgets('sem canWrite, não mostra ações de editar/apagar', (tester) async {
      await tester.pumpWidget(buildScreen());

      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('com canWrite, mostra ações de editar/apagar', (tester) async {
      await tester.pumpWidget(buildScreen(canWrite: true));

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('apagar pede confirmação e remove a entrada', (tester) async {
      final repo = MockVaultRepository();
      when(() => repo.deleteEntry(entry.id)).thenAnswer((_) async {});

      await tester.pumpWidget(MaterialApp(
        home: VaultEntryDetailScreen(entry: entry, canWrite: true, repository: repo),
      ));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete entry?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      verify(() => repo.deleteEntry(entry.id)).called(1);
    });
  });
}

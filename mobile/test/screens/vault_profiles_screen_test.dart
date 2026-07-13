import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_profiles_screen.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Repositório mockado, não real — VaultRepository faz I/O real de arquivo
// (dart:io), que nunca resolve dentro da zona FakeAsync de um widget test
// (achado da Sessão 98, validação manual dos testes escritos na Sessão 97:
// travava pumpAndSettle indefinidamente). O CRUD real do repositório já é
// coberto por vault_repository_test.dart (testes puros, sem widget).
class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repo;

  setUp(() {
    repo = MockVaultRepository();
  });

  Widget buildScreen() => MaterialApp(home: VaultProfilesScreen(repository: repo));

  testWidgets('mostra "nenhum perfil" em vault vazio', (tester) async {
    when(() => repo.listProfileNames()).thenAnswer((_) async => []);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('No profiles created yet.'), findsOneWidget);
  });

  testWidgets('adiciona um perfil novo', (tester) async {
    when(() => repo.listProfileNames()).thenAnswer((_) async => []);
    when(() => repo.addProfile('Trabalho')).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    when(() => repo.listProfileNames()).thenAnswer((_) async => ['Trabalho']);

    await tester.enterText(find.byType(TextField), 'Trabalho');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Trabalho'), findsOneWidget);
    verify(() => repo.addProfile('Trabalho')).called(1);
  });

  testWidgets('apaga um perfil com confirmação', (tester) async {
    when(() => repo.listProfileNames()).thenAnswer((_) async => ['Trabalho']);
    when(() => repo.deleteProfile('Trabalho')).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    when(() => repo.listProfileNames()).thenAnswer((_) async => []);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete profile?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No profiles created yet.'), findsOneWidget);
    verify(() => repo.deleteProfile('Trabalho')).called(1);
  });
}

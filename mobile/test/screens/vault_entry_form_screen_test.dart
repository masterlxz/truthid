import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_entry_form_screen.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Repositório mockado, não real — VaultRepository faz I/O real de arquivo,
// que nunca resolve num widget test (mesmo motivo documentado em
// vault_entry_detail_screen_test.dart, achado na Sessão 98). O CRUD real já
// é coberto por vault_repository_test.dart.
class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  final documentEntry = VaultEntry(
    id: '1',
    site: '',
    url: '',
    username: '',
    password: '',
    notes: '',
    type: EntryType.document,
    document: const DocumentData(
      name: 'RG',
      fileName: 'rg.pdf',
      fileData: 'base64-fake-content',
      fileSizeBytes: 123,
      mimeType: 'application/pdf',
    ),
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  late MockVaultRepository repo;

  setUpAll(() {
    registerFallbackValue(documentEntry);
  });

  setUp(() {
    repo = MockVaultRepository();
    when(() => repo.listProfileNames()).thenAnswer((_) async => <String>[]);
  });

  Widget buildScreen({VaultEntry? entry}) => MaterialApp(
        home: VaultEntryFormScreen(entry: entry, repository: repo),
      );

  ElevatedButton saveButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'));

  // Preenche os campos obrigatórios do tipo "address", nesta ordem — mirror
  // exato da ordem em que os TextField de endereço são renderizados no
  // formulário (VaultEntryFormScreen.build). Complemento/telefone (opcionais)
  // ficam de fora de propósito.
  Future<void> fillRequiredAddressFields(WidgetTester tester) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Home'); // label
    await tester.enterText(fields.at(1), 'Alice'); // full name
    await tester.enterText(fields.at(2), 'Main St'); // street
    await tester.enterText(fields.at(3), '123'); // number
    await tester.enterText(fields.at(5), 'Downtown'); // neighborhood
    await tester.enterText(fields.at(6), 'Springfield'); // city
    await tester.enterText(fields.at(7), 'IL'); // state
    await tester.enterText(fields.at(8), '00000-000'); // zip code
    await tester.enterText(fields.at(9), 'US'); // country
    await tester.pump();
  }

  testWidgets('trocar de chip mostra/esconde o grupo de campo certo', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Site *'), findsOneWidget);
    expect(find.text('Street *'), findsNothing);

    await tester.tap(find.text('🏠 Address'));
    await tester.pump();

    expect(find.text('Site *'), findsNothing);
    expect(find.text('Street *'), findsOneWidget);
  });

  testWidgets('Salvar fica desabilitado até os campos obrigatórios do tipo endereço', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('🏠 Address'));
    await tester.pump();

    expect(saveButton(tester).onPressed, isNull);

    await fillRequiredAddressFields(tester);

    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'editar um documento e trocar pro tipo endereço zera o grupo document ao salvar '
    '(regressão: mesmo bug achado no Desktop na 15.2)',
    (tester) async {
      when(() => repo.updateEntry(any()))
          .thenAnswer((invocation) async => invocation.positionalArguments.single as VaultEntry);

      await tester.pumpWidget(buildScreen(entry: documentEntry));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🏠 Address'));
      await tester.pump();
      await fillRequiredAddressFields(tester);

      final saveFinder = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(saveFinder);
      await tester.pumpAndSettle();
      await tester.tap(saveFinder);
      await tester.pumpAndSettle();

      final captured = verify(() => repo.updateEntry(captureAny())).captured;
      expect(captured, hasLength(1));
      final saved = captured.single as VaultEntry;
      expect(saved.type, EntryType.address);
      expect(saved.document, isNull);
      expect(saved.address?.city, 'Springfield');
    },
  );
}

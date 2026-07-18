import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/vault_backup_screen.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Repositório mockado, mesmo padrão de vault_profiles_screen_test.dart —
// VaultRepository faz I/O real de arquivo, que nunca resolve dentro da zona
// FakeAsync de um widget test.
//
// Os botões "Export backup"/"Import" chamam FilePicker.platform.saveFile()/
// pickFiles() diretamente (não injetado via construtor), que não tem
// implementação de plataforma registrada no ambiente de teste — por isso
// este arquivo testa só a lógica de validação de senha (habilita/desabilita
// botão) e a renderização inicial, sem de fato tocar nos botões que chamam
// o file_picker.
class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repo;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repo = MockVaultRepository();
  });

  Widget buildScreen() => MaterialApp(home: VaultBackupScreen(repository: repo));

  // A tela usa um ListView (export + import numa coluna comprida) — o
  // conteúdo abaixo da dobra não é montado no viewport padrão de teste
  // (ListView virtualiza via sliver mesmo com uma lista fixa de children).
  // Aumenta a "tela" de teste pra caber tudo sem precisar rolar.
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
  }

  testWidgets('renderiza as seções de exportar e importar', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Export'), findsOneWidget);
    // "Import" aparece 2x: o título da seção e o rótulo do botão de ação.
    expect(find.text('Import'), findsNWidgets(2));
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Choose .truthid-backup file'), findsOneWidget);
  });

  testWidgets('botão Export backup começa desabilitado (senhas vazias)', (tester) async {
    await pumpScreen(tester);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Export backup'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('botão Export backup fica desabilitado quando as senhas não coincidem',
      (tester) async {
    await pumpScreen(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'senha-123');
    await tester.enterText(fields.at(1), 'senha-456');
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Export backup'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('botão Export backup fica habilitado quando as senhas coincidem',
      (tester) async {
    await pumpScreen(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'senha-123');
    await tester.enterText(fields.at(1), 'senha-123');
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Export backup'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('botão Import começa desabilitado (sem arquivo escolhido)', (tester) async {
    await pumpScreen(tester);

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Import'),
    );
    expect(button.onPressed, isNull);
    verifyNever(() => repo.importBackup(any(), any()));
  });
}

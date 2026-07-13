import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/screens/vault_profiles_screen.dart';
import 'package:truthid_mobile/services/vault_cipher_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

class _FakeCipherService extends VaultCipherService {
  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async => plaintext;

  @override
  Future<Uint8List> decrypt(Uint8List blob) async => blob;
}

void main() {
  late Directory tempDir;
  late VaultRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_profiles_test_');
    repo = VaultRepository(
      cipherService: _FakeCipherService(),
      testPath: '${tempDir.path}/vault.enc',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Widget buildScreen() => MaterialApp(home: VaultProfilesScreen(repository: repo));

  testWidgets('mostra "nenhum perfil" em vault vazio', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('No profiles created yet.'), findsOneWidget);
  });

  testWidgets('adiciona um perfil novo', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Trabalho');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Trabalho'), findsOneWidget);
    expect(await repo.listProfileNames(), equals(['Trabalho']));
  });

  testWidgets('apaga um perfil com confirmação', (tester) async {
    await repo.addProfile('Trabalho');
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete profile?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No profiles created yet.'), findsOneWidget);
    expect(await repo.listProfileNames(), isEmpty);
  });
}

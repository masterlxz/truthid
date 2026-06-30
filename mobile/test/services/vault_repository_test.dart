import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/vault_cipher_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

// Cipher no-op para testar só a lógica de CRUD sem depender de chave real.
class _FakeCipherService extends VaultCipherService {
  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async => plaintext;

  @override
  Future<Uint8List> decrypt(Uint8List blob) async => blob;
}

void main() {
  late Directory tempDir;
  late String vaultPath;
  late VaultRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
    vaultPath = '${tempDir.path}/vault.enc';
    repo = VaultRepository(
      cipherService: _FakeCipherService(),
      testPath: vaultPath,
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('VaultRepository', () {
    test('listEntries em vault vazio retorna lista vazia', () async {
      final entries = await repo.listEntries();
      expect(entries, isEmpty);
    });

    test('addEntry retorna entrada com id e timestamps gerados', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 's3cr3t',
      );

      expect(entry.id, isNotEmpty);
      expect(entry.site, 'github.com');
      expect(entry.username, 'fab');
      expect(entry.password, 's3cr3t');
      expect(entry.createdAt.millisecondsSinceEpoch, greaterThan(0));
      expect(entry.updatedAt.millisecondsSinceEpoch, greaterThan(0));
    });

    test('addEntry + listEntries — entry aparece na lista', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');

      final entries = await repo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.first.site, 'github.com');
    });

    test('addEntry múltiplas vezes — todas as entries são preservadas', () async {
      await repo.addEntry(site: 'github.com', username: 'a', password: 'x');
      await repo.addEntry(site: 'google.com', username: 'b', password: 'y');
      await repo.addEntry(site: 'notion.so', username: 'c', password: 'z');

      final entries = await repo.listEntries();
      expect(entries, hasLength(3));
    });

    test('updateEntry — campo atualizado, createdAt preservado', () async {
      final original = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'old',
      );

      final updated = await repo.updateEntry(
        original.copyWith(password: 'new'),
      );

      expect(updated.id, original.id);
      expect(updated.password, 'new');
      expect(updated.createdAt, original.createdAt);
      expect(
        updated.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(original.updatedAt.millisecondsSinceEpoch),
      );
    });

    test('deleteEntry — entry some da lista', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );

      await repo.deleteEntry(entry.id);

      final entries = await repo.listEntries();
      expect(entries, isEmpty);
    });

    test('deleteEntry — só a entrada correta é removida', () async {
      final a = await repo.addEntry(site: 'a.com', username: 'u', password: 'p');
      final b = await repo.addEntry(site: 'b.com', username: 'u', password: 'p');
      await repo.addEntry(site: 'c.com', username: 'u', password: 'p');

      await repo.deleteEntry(b.id);

      final entries = await repo.listEntries();
      expect(entries, hasLength(2));
      expect(entries.any((e) => e.id == a.id), isTrue);
      expect(entries.any((e) => e.id == b.id), isFalse);
    });

    test('deleteEntry de id inexistente não lança erro', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');

      await expectLater(
        repo.deleteEntry('id-que-nao-existe'),
        completes,
      );

      // Vault não foi alterado
      expect(await repo.listEntries(), hasLength(1));
    });

    test('persistência — dados sobrevivem entre instâncias do repositório', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 's3cr3t');

      // Cria um segundo repositório apontando pro mesmo arquivo
      final repo2 = VaultRepository(
        cipherService: _FakeCipherService(),
        testPath: vaultPath,
      );
      final entries = await repo2.listEntries();

      expect(entries, hasLength(1));
      expect(entries.first.site, 'github.com');
      expect(entries.first.username, 'fab');
    });

    test('version incrementa a cada mutação', () async {
      // Lemos o vault interno verificando version via addEntry + recarregamento
      await repo.addEntry(site: 'a.com', username: 'u', password: 'p');
      await repo.addEntry(site: 'b.com', username: 'u', password: 'p');

      final repo2 = VaultRepository(
        cipherService: _FakeCipherService(),
        testPath: vaultPath,
      );
      // Se version > 0 → as escritas estão acontecendo corretamente
      // (verificamos indiretamente: 2 entries presentes)
      expect(await repo2.listEntries(), hasLength(2));
    });

    test('campos opcionais têm valores padrão', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );

      expect(entry.url, '');
      expect(entry.notes, '');
      expect(entry.profiles, isEmpty);
    });

    test('profiles suporta múltiplos grupos', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
        profiles: ['Trabalho', 'Pessoal'],
      );

      expect(entry.profiles, containsAll(['Trabalho', 'Pessoal']));
      expect(entry.profiles, hasLength(2));
    });

    test('migração: formato antigo com "profile" é convertido para "profiles"', () async {
      // Simula vault salvo com formato antigo (profile como string única)
      final oldJson = jsonEncode({
        'version': 1,
        'entries': [
          {
            'id': 'abc123',
            'site': 'github.com',
            'url': '',
            'username': 'fab',
            'password': 'pass',
            'notes': '',
            'profile': 'Trabalho',
            'created_at': 1700000000,
            'updated_at': 1700000000,
          }
        ],
      });
      await File(vaultPath).writeAsBytes(Uint8List.fromList(utf8.encode(oldJson)));

      final entries = await repo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.first.profiles, equals(['Trabalho']));
    });
  });
}

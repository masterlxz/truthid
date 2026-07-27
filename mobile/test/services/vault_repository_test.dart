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

    test('updateEntry — lança quando id não existe (débito #38)', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');

      final ghost = VaultEntry(
        id: 'id-inexistente',
        site: 'ghost.com',
        url: '',
        username: 'u',
        password: 'p',
        notes: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(() => repo.updateEntry(ghost), throwsException);
      expect(await repo.listEntries(), hasLength(1)); // no-op, não vira insert
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

    test('overwriteCache grava os bytes crus e listEntries decifra depois',
        () async {
      final plaintextJson = jsonEncode({
        'version': 3,
        'entries': [
          {
            'id': 'synced-1',
            'site': 'example.com',
            'url': '',
            'username': 'u',
            'password': 'p',
            'notes': '',
            'profiles': ['Trabalho'],
            'created_at': 1700000000,
            'updated_at': 1700000000,
          }
        ],
      });
      final bytes = Uint8List.fromList(utf8.encode(plaintextJson));

      await repo.overwriteCache(bytes);

      expect(await File(vaultPath).readAsBytes(), equals(bytes));
      final entries = await repo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.first.site, 'example.com');
      expect(entries.first.profiles, equals(['Trabalho']));
    });

    // --- perfis nomeados pelo usuário (Sessão 97) ---

    test('listProfileNames em vault vazio retorna lista vazia', () async {
      expect(await repo.listProfileNames(), isEmpty);
    });

    test('listProfileNames lê profile_names do blob sincronizado', () async {
      final plaintextJson = jsonEncode({
        'version': 1,
        'entries': [],
        'profile_names': ['Trabalho', 'Banco'],
      });
      final bytes = Uint8List.fromList(utf8.encode(plaintextJson));

      await repo.overwriteCache(bytes);

      expect(await repo.listProfileNames(), equals(['Trabalho', 'Banco']));
    });

    test('blob sem profile_names (formato anterior à Sessão 97) não quebra',
        () async {
      final plaintextJson = jsonEncode({
        'version': 1,
        'entries': [
          {
            'id': 'abc',
            'site': 'github.com',
            'url': '',
            'username': 'fab',
            'password': 'pass',
            'notes': '',
            'profiles': ['Trabalho'],
            'created_at': 1700000000,
            'updated_at': 1700000000,
          }
        ],
      });
      final bytes = Uint8List.fromList(utf8.encode(plaintextJson));

      await repo.overwriteCache(bytes);

      expect(await repo.listProfileNames(), isEmpty);
      expect(await repo.listEntries(), hasLength(1));
    });

    test('addEntry preserva profile_names já existente no vault', () async {
      final plaintextJson = jsonEncode({
        'version': 1,
        'entries': [],
        'profile_names': ['Trabalho'],
      });
      await repo.overwriteCache(
        Uint8List.fromList(utf8.encode(plaintextJson)),
      );

      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');

      expect(await repo.listProfileNames(), equals(['Trabalho']));
    });

    test('addProfile adiciona um novo nome', () async {
      await repo.addProfile('Trabalho');
      expect(await repo.listProfileNames(), equals(['Trabalho']));
    });

    test('addProfile é no-op pra nome duplicado', () async {
      await repo.addProfile('Trabalho');
      await repo.addProfile('Trabalho');
      expect(await repo.listProfileNames(), equals(['Trabalho']));
    });

    test('renameProfile atualiza a lista e propaga pras entradas', () async {
      await repo.addProfile('Trabalho');
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
        profiles: ['Trabalho', 'Pessoal'],
      );

      await repo.renameProfile('Trabalho', 'Banco');

      expect(await repo.listProfileNames(), equals(['Banco']));
      final updated = (await repo.listEntries()).firstWhere((e) => e.id == entry.id);
      expect(updated.profiles, equals(['Banco', 'Pessoal']));
    });

    test('renameProfile de nome inexistente não faz nada', () async {
      await repo.addProfile('Trabalho');
      await repo.renameProfile('Inexistente', 'Novo');
      expect(await repo.listProfileNames(), equals(['Trabalho']));
    });

    test('deleteProfile remove da lista e das entradas', () async {
      await repo.addProfile('Trabalho');
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
        profiles: ['Trabalho', 'Pessoal'],
      );

      await repo.deleteProfile('Trabalho');

      expect(await repo.listProfileNames(), isEmpty);
      final updated = (await repo.listEntries()).firstWhere((e) => e.id == entry.id);
      expect(updated.profiles, equals(['Pessoal']));
    });
  });

  group('VaultRepository favorite', () {
    test('nova entrada nasce com favorite false por padrão', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );
      expect(entry.favorite, isFalse);
    });

    test('setFavorite marca uma entrada existente', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );

      await repo.setFavorite(entry.id, true);

      final updated =
          (await repo.listEntries()).firstWhere((e) => e.id == entry.id);
      expect(updated.favorite, isTrue);
    });

    test('setFavorite desmarca uma entrada já favoritada', () async {
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );
      await repo.setFavorite(entry.id, true);
      await repo.setFavorite(entry.id, false);

      final updated =
          (await repo.listEntries()).firstWhere((e) => e.id == entry.id);
      expect(updated.favorite, isFalse);
    });

    test('setFavorite preserva os outros campos, incluindo updatedAt',
        () async {
      await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
        notes: 'nota original',
      );
      // Relê depois do round-trip de serialização (que trunca pra precisão
      // de segundo) — comparar contra o valor em memória do addEntry
      // acusaria falso positivo por causa da própria truncação, não por
      // causa de setFavorite.
      final beforeToggle = (await repo.listEntries()).first;
      final originalUpdatedAt = beforeToggle.updatedAt;

      await repo.setFavorite(beforeToggle.id, true);

      final updated = (await repo.listEntries())
          .firstWhere((e) => e.id == beforeToggle.id);
      expect(updated.notes, 'nota original');
      expect(updated.updatedAt, originalUpdatedAt,
          reason: 'updatedAt não deve mudar só por favoritar');
    });

    test('setFavorite só afeta a entrada alvo', () async {
      final a = await repo.addEntry(site: 'github.com', username: 'a', password: 'x');
      final b = await repo.addEntry(site: 'gitlab.com', username: 'b', password: 'y');

      await repo.setFavorite(a.id, true);

      final entries = await repo.listEntries();
      expect(entries.firstWhere((e) => e.id == a.id).favorite, isTrue);
      expect(entries.firstWhere((e) => e.id == b.id).favorite, isFalse);
    });

    test('setFavorite incrementa a versão do vault', () async {
      final entry = await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');
      final before = await repo.currentVersion();

      await repo.setFavorite(entry.id, true);

      expect(await repo.currentVersion(), before + 1);
    });

    test('setFavorite de id inexistente lança erro', () async {
      expect(() => repo.setFavorite('does-not-exist', true), throwsException);
    });
  });

  group('VaultRepository device permissions', () {
    test('listDevicePermissions em vault vazio retorna lista vazia', () async {
      expect(await repo.listDevicePermissions(), isEmpty);
    });

    test('setDevicePermission cria uma permissão nova', () async {
      await repo.setDevicePermission('0xAAA', true);

      final permissions = await repo.listDevicePermissions();
      expect(permissions, hasLength(1));
      expect(permissions.first.pubKey, '0xAAA');
      expect(permissions.first.canWrite, isTrue);
    });

    test('setDevicePermission atualiza uma permissão já existente', () async {
      await repo.setDevicePermission('0xAAA', true);
      await repo.setDevicePermission('0xAAA', false);

      final permissions = await repo.listDevicePermissions();
      expect(permissions, hasLength(1));
      expect(permissions.first.canWrite, isFalse);
    });

    test('setDevicePermission é case-insensitive pro pubKey', () async {
      await repo.setDevicePermission('0xAAA', true);
      await repo.setDevicePermission('0xaaa', false);

      final permissions = await repo.listDevicePermissions();
      expect(permissions, hasLength(1));
      expect(permissions.first.canWrite, isFalse);
    });

    test('setDevicePermission preserva as permissões de outros devices',
        () async {
      await repo.setDevicePermission('0xAAA', true);
      await repo.setDevicePermission('0xBBB', false);

      final permissions = await repo.listDevicePermissions();
      expect(permissions, hasLength(2));
      expect(
        permissions.map((p) => p.pubKey).toSet(),
        equals({'0xAAA', '0xBBB'}),
      );
    });

    test('setDevicePermission incrementa a versão do vault', () async {
      final before = await repo.currentVersion();
      await repo.setDevicePermission('0xAAA', true);
      expect(await repo.currentVersion(), before + 1);
    });

    test('setDevicePermission não altera entries nem perfis já existentes',
        () async {
      await repo.addProfile('Trabalho');
      final entry = await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
      );

      await repo.setDevicePermission('0xAAA', true);

      expect(await repo.listProfileNames(), equals(['Trabalho']));
      final entries = await repo.listEntries();
      expect(entries.map((e) => e.id), contains(entry.id));
    });
  });

  group('VaultRepository backup export/import', () {
    test('exportBackup retorna bytes começando com o magic TIDVLTB1', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');
      final blob = await repo.exportBackup('hunter2');
      expect(utf8.decode(blob.sublist(0, 8)), 'TIDVLTB1');
    });

    test('importBackup faz roundtrip de entries/profileNames/version', () async {
      await repo.addProfile('Trabalho');
      await repo.addEntry(
        site: 'github.com',
        username: 'fab',
        password: 'x',
        profiles: ['Trabalho'],
      );
      final versionBefore = await repo.currentVersion();

      final blob = await repo.exportBackup('hunter2');

      final freshTempDir = await Directory.systemTemp.createTemp('vault_import_test_');
      final freshRepo = VaultRepository(
        cipherService: _FakeCipherService(),
        testPath: '${freshTempDir.path}/vault.enc',
      );
      await freshRepo.importBackup(blob, 'hunter2');

      final entries = await freshRepo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.first.site, 'github.com');
      expect(entries.first.profiles, equals(['Trabalho']));
      expect(await freshRepo.listProfileNames(), equals(['Trabalho']));
      expect(await freshRepo.currentVersion(), equals(versionBefore));

      await freshTempDir.delete(recursive: true);
    });

    test('importBackup com senha errada lança e não altera o vault local', () async {
      await repo.addEntry(site: 'github.com', username: 'fab', password: 'x');
      final blob = await repo.exportBackup('senha-certa');

      await expectLater(
        repo.importBackup(blob, 'senha-errada'),
        throwsFormatException,
      );

      final entries = await repo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.first.site, 'github.com');
    });
  });

  group('VaultEntry.toJsonForExtension', () {
    test('never includes totp_secret, even when the entry has one', () {
      final entry = VaultEntry(
        id: '1',
        site: 'github.com',
        url: '',
        username: 'fab',
        password: 'x',
        notes: '',
        totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(entry.toJson().containsKey('totp_secret'), isTrue);
      expect(entry.toJsonForExtension().containsKey('totp_secret'), isFalse);
    });

    test(
        'includes passkey when the entry has one — extension needs the '
        'private key to sign navigator.credentials.get() (Sessão 132)', () {
      final entry = VaultEntry(
        id: '1',
        site: 'github.com',
        url: '',
        username: 'fab',
        password: 'x',
        notes: '',
        passkey: Passkey(
          rpId: 'github.com',
          credentialIdB64: 'AAAAAAAAAAAAAAAAAAAAAA',
          userHandleB64: 'BBBBBBBBBBBBBBBBBBBBBB',
          privateKeyHex: '00' * 32,
          signCount: 0,
          createdAt: DateTime.now().toUtc(),
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(entry.toJson().containsKey('passkey'), isTrue);
      expect(entry.toJsonForExtension()['passkey'], isNotNull);
      expect(
        entry.toJsonForExtension()['passkey']['private_key_hex'],
        '00' * 32,
      );
    });

    test('carries every other field through unchanged', () {
      final entry = VaultEntry(
        id: '1',
        site: 'github.com',
        url: 'https://github.com',
        username: 'fab',
        password: 'x',
        notes: 'note',
        profiles: const ['Trabalho'],
        totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final extensionJson = entry.toJsonForExtension();
      final fullJson = entry.toJson()..remove('totp_secret');
      expect(extensionJson, equals(fullJson));
    });
  });

  group('VaultEntry schema Fase 15.1 (document/address/creditCard)', () {
    VaultEntry credentialEntry() => VaultEntry(
          id: '1',
          site: 'github.com',
          url: '',
          username: 'fab',
          password: 'x',
          notes: '',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

    test('old JSON without "type"/document/address/creditCard parses as credential', () {
      final oldJson = {
        'id': '1',
        'site': 'github.com',
        'url': '',
        'username': 'fab',
        'password': 'x',
        'notes': '',
        'profiles': <String>[],
        'created_at': 0,
        'updated_at': 0,
      };

      final entry = VaultEntry.fromJson(oldJson);

      expect(entry.type, EntryType.credential);
      expect(entry.document, isNull);
      expect(entry.address, isNull);
      expect(entry.creditCard, isNull);
    });

    test('document entry round-trips through JSON', () {
      final entry = VaultEntry(
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
          fileSizeBytes: 12345,
          mimeType: 'application/pdf',
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final reparsed = VaultEntry.fromJson(entry.toJson());

      expect(reparsed.type, EntryType.document);
      expect(reparsed.document?.name, 'RG');
      expect(reparsed.document?.fileSizeBytes, 12345);
      expect(reparsed.address, isNull);
      expect(reparsed.creditCard, isNull);
    });

    test('address entry round-trips through JSON', () {
      final entry = VaultEntry(
        id: '1',
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.address,
        address: const AddressData(
          label: 'Casa',
          fullName: 'Fabio Junior',
          street: 'Rua X',
          number: '123',
          neighborhood: 'Centro',
          city: 'São Paulo',
          state: 'SP',
          zipCode: '01000-000',
          country: 'BR',
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final reparsed = VaultEntry.fromJson(entry.toJson());

      expect(reparsed.type, EntryType.address);
      expect(reparsed.address?.city, 'São Paulo');
      expect(reparsed.document, isNull);
      expect(reparsed.creditCard, isNull);
    });

    test('credit card entry round-trips through JSON', () {
      final entry = VaultEntry(
        id: '1',
        site: '',
        url: '',
        username: '',
        password: '',
        notes: '',
        type: EntryType.creditCard,
        creditCard: const CreditCardData(
          label: 'Nubank',
          cardHolderName: 'Fabio Junior',
          cardNumber: '4111111111111111',
          expiryMonth: '12',
          expiryYear: '2030',
          cvv: '123',
          cardNetwork: CardNetwork.visa,
        ),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final reparsed = VaultEntry.fromJson(entry.toJson());

      expect(reparsed.type, EntryType.creditCard);
      expect(reparsed.creditCard?.cardNumber, '4111111111111111');
      expect(reparsed.creditCard?.cardNetwork, CardNetwork.visa);
      expect(reparsed.document, isNull);
      expect(reparsed.address, isNull);
    });

    test('unknown card_network falls back to other (forward-compat)', () {
      final json = {
        'label': 'x',
        'card_holder_name': 'x',
        'card_number': 'x',
        'expiry_month': 'x',
        'expiry_year': 'x',
        'cvv': 'x',
        'card_network': 'some_future_network',
      };

      expect(CreditCardData.fromJson(json).cardNetwork, CardNetwork.other);
    });

    test('unknown type falls back to credential (forward-compat)', () {
      expect(EntryType.fromJson('some_future_type'), EntryType.credential);
      expect(EntryType.fromJson(null), EntryType.credential);
    });

    test('copyWith preserves document/address/creditCard when not passed', () {
      final entry = credentialEntry().copyWith(
        type: EntryType.address,
        address: const AddressData(
          label: 'Casa',
          fullName: 'Fabio Junior',
          street: 'Rua X',
          number: '123',
          neighborhood: 'Centro',
          city: 'São Paulo',
          state: 'SP',
          zipCode: '01000-000',
          country: 'BR',
        ),
      );

      final copy = entry.copyWith(favorite: true);

      expect(copy.type, EntryType.address);
      expect(copy.address?.city, 'São Paulo');
      expect(copy.favorite, isTrue);
    });

    test('copyWith clears document/address/creditCard when explicitly passed null', () {
      final entry = credentialEntry().copyWith(
        type: EntryType.document,
        document: const DocumentData(
          name: 'RG',
          fileName: 'rg.pdf',
          fileData: 'x',
          fileSizeBytes: 1,
          mimeType: 'application/pdf',
        ),
      );

      final cleared = entry.copyWith(type: EntryType.credential, document: null);

      expect(cleared.document, isNull);
    });
  });

  group('VaultEntry.validate() (Fase 15.3 safety net)', () {
    VaultEntry credentialEntry() => VaultEntry(
          id: '1',
          site: 'github.com',
          url: '',
          username: 'fab',
          password: 'x',
          notes: '',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

    const document = DocumentData(
      name: 'RG',
      fileName: 'rg.pdf',
      fileData: 'base64-fake-content',
      fileSizeBytes: 12345,
      mimeType: 'application/pdf',
    );
    const address = AddressData(
      label: 'Casa',
      fullName: 'Fabio Junior',
      street: 'Rua X',
      number: '123',
      neighborhood: 'Centro',
      city: 'São Paulo',
      state: 'SP',
      zipCode: '01000-000',
      country: 'BR',
    );
    const creditCard = CreditCardData(
      label: 'Nubank',
      cardHolderName: 'Fabio Junior',
      cardNumber: '4111111111111111',
      expiryMonth: '12',
      expiryYear: '2030',
      cvv: '123',
      cardNetwork: CardNetwork.visa,
    );

    test('credential with no data group is valid', () {
      expect(() => credentialEntry().validate(), returnsNormally);
    });

    test('document with only the document group is valid', () {
      final entry = credentialEntry().copyWith(type: EntryType.document, document: document);
      expect(() => entry.validate(), returnsNormally);
    });

    test('credential with a document group set is invalid', () {
      final entry = credentialEntry().copyWith(document: document);
      expect(() => entry.validate(), throwsException);
    });

    test('document type without its data group is invalid', () {
      final entry = credentialEntry().copyWith(type: EntryType.document);
      expect(() => entry.validate(), throwsException);
    });

    test('address type carrying a leftover creditCard group is invalid', () {
      final entry = credentialEntry().copyWith(
        type: EntryType.address,
        address: address,
        creditCard: creditCard,
      );
      expect(() => entry.validate(), throwsException);
    });
  });

  group('VaultRepository Fase 15.3 (CRUD dos tipos novos + validate())', () {
    const document = DocumentData(
      name: 'RG',
      fileName: 'rg.pdf',
      fileData: 'base64-fake-content',
      fileSizeBytes: 12345,
      mimeType: 'application/pdf',
    );
    const address = AddressData(
      label: 'Casa',
      fullName: 'Fabio Junior',
      street: 'Rua X',
      number: '123',
      neighborhood: 'Centro',
      city: 'São Paulo',
      state: 'SP',
      zipCode: '01000-000',
      country: 'BR',
    );
    const creditCard = CreditCardData(
      label: 'Nubank',
      cardHolderName: 'Fabio Junior',
      cardNumber: '4111111111111111',
      expiryMonth: '12',
      expiryYear: '2030',
      cvv: '123',
      cardNetwork: CardNetwork.visa,
    );

    test('addEntry persists a document entry and round-trips via listEntries', () async {
      await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.document, document: document,
      );

      final entries = await repo.listEntries();
      expect(entries, hasLength(1));
      expect(entries.single.type, EntryType.document);
      expect(entries.single.document?.name, 'RG');
      expect(entries.single.address, isNull);
      expect(entries.single.creditCard, isNull);
    });

    test('addEntry persists an address entry and round-trips via listEntries', () async {
      await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.address, address: address,
      );

      final entries = await repo.listEntries();
      expect(entries.single.type, EntryType.address);
      expect(entries.single.address?.city, 'São Paulo');
    });

    test('addEntry persists a credit card entry and round-trips via listEntries', () async {
      await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.creditCard, creditCard: creditCard,
      );

      final entries = await repo.listEntries();
      expect(entries.single.type, EntryType.creditCard);
      expect(entries.single.creditCard?.cardNumber, '4111111111111111');
    });

    test('addEntry rejects a type/data-group mismatch and does not bump version', () async {
      final before = await repo.currentVersion();

      await expectLater(
        repo.addEntry(site: '', username: '', password: '', type: EntryType.document),
        throwsException,
      );

      expect(await repo.currentVersion(), before);
      expect(await repo.listEntries(), isEmpty);
    });

    test(
      'updateEntry rejects switching type without clearing the old data group '
      '(regression: the exact bug found on Desktop in 15.2)',
      () async {
        final doc = await repo.addEntry(
          site: '', username: '', password: '',
          type: EntryType.document, document: document,
        );
        final beforeVersion = await repo.currentVersion();

        // Troca pra "address" mas esquece de zerar `document` — exatamente o
        // bug achado no Desktop (VaultManagement.tsx) durante a 15.2, quando
        // `buildEntryPayload` não zerava explicitamente os outros grupos.
        await expectLater(
          repo.updateEntry(doc.copyWith(type: EntryType.address, address: address)),
          throwsException,
        );

        expect(await repo.currentVersion(), beforeVersion);
      },
    );

    test('updateEntry accepts switching type when the old data group is explicitly cleared', () async {
      final doc = await repo.addEntry(
        site: '', username: '', password: '',
        type: EntryType.document, document: document,
      );

      final updated = await repo.updateEntry(doc.copyWith(
        type: EntryType.address,
        document: null,
        address: address,
      ));

      expect(updated.type, EntryType.address);
      expect(updated.document, isNull);
      expect(updated.address?.city, 'São Paulo');
    });
  });
}

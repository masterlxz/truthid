import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/ios_autofill_identity_service.dart';
import 'package:truthid_mobile/services/vault_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('truthid/ios_autofill_identities');

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  VaultEntry credential({required String id, required String site, required String url, required String username}) =>
      VaultEntry(
        id: id,
        site: site,
        url: url,
        username: username,
        password: 'hunter2',
        notes: '',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

  test('só entradas do tipo credential viram identidades, com hostname derivado da URL', () async {
    List<dynamic>? received;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'syncCredentialIdentities') {
        received = call.arguments as List<dynamic>;
      }
      return null;
    });

    final entries = [
      credential(id: 'c1', site: 'GitHub', url: 'https://github.com/login', username: 'alice'),
    ];

    await IosAutofillIdentityService().syncIdentities(entries);

    expect(received, hasLength(1));
    expect(received!.first, {
      'id': 'c1',
      'serviceIdentifier': 'github.com',
      'username': 'alice',
    });
  });

  test('sem URL válida, cai pro nome do site sanitizado', () async {
    List<dynamic>? received;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call.arguments as List<dynamic>;
      return null;
    });

    final entries = [
      credential(id: 'c1', site: 'My Bank!', url: '', username: 'bob'),
    ];

    await IosAutofillIdentityService().syncIdentities(entries);

    expect((received!.first as Map)['serviceIdentifier'], 'mybank');
  });

  test('entradas de endereço/cartão não viram identidades — só credential', () async {
    List<dynamic>? received;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call.arguments as List<dynamic>;
      return null;
    });

    final address = VaultEntry(
      id: 'addr1',
      site: '',
      url: '',
      username: '',
      password: '',
      notes: '',
      type: EntryType.address,
      address: const AddressData(
        label: 'Home',
        fullName: 'Alice',
        street: 'Main St',
        number: '1',
        neighborhood: 'Centro',
        city: 'Springfield',
        state: 'IL',
        zipCode: '00000',
        country: 'US',
      ),
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final login = credential(id: 'c1', site: 'a.com', url: '', username: 'x');

    await IosAutofillIdentityService().syncIdentities([address, login]);

    expect(received, hasLength(1));
    expect((received!.first as Map)['id'], 'c1');
  });

  test('canal ausente (Android, ou build sem o código nativo) não lança', () async {
    // Sem setMockMethodCallHandler — a chamada bate um MissingPluginException,
    // que syncIdentities deve engolir silenciosamente.
    final entries = [credential(id: 'c1', site: 'a.com', url: '', username: 'x')];
    await expectLater(IosAutofillIdentityService().syncIdentities(entries), completes);
  });
}

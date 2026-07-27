import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/vault_repository.dart';
import 'package:truthid_mobile/widgets/address_summary.dart';

void main() {
  const address = AddressData(
    label: 'Home',
    fullName: 'Alice Example',
    street: 'Main St',
    number: '123',
    neighborhood: 'Downtown',
    city: 'Springfield',
    state: 'IL',
    zipCode: '00000-000',
    country: 'US',
  );

  test('addressTitle devolve o label', () {
    expect(addressTitle(address), 'Home');
  });

  test('addressSubtitle monta rua/número · cidade/estado · CEP', () {
    expect(addressSubtitle(address), 'Main St, 123 · Springfield/IL · 00000-000');
  });
}

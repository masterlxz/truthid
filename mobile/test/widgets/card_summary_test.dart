import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/vault_repository.dart';
import 'package:truthid_mobile/widgets/card_summary.dart';

void main() {
  const card = CreditCardData(
    label: 'Nubank',
    cardHolderName: 'Alice Example',
    cardNumber: '4111111111111234',
    expiryMonth: '09',
    expiryYear: '2029',
    cvv: '123',
    cardNetwork: CardNetwork.visa,
  );

  test('cardTitle devolve o label', () {
    expect(cardTitle(card), 'Nubank');
  });

  test('cardSubtitle mascara o número, só mostra os últimos 4 dígitos', () {
    expect(cardSubtitle(card), 'visa •••• 1234 · 09/2029');
  });

  test('cardSubtitle não quebra com número menor que 4 dígitos', () {
    const shortCard = CreditCardData(
      label: 'Test',
      cardHolderName: 'Bob',
      cardNumber: '12',
      expiryMonth: '01',
      expiryYear: '2030',
      cvv: '000',
      cardNetwork: CardNetwork.other,
    );
    expect(cardSubtitle(shortCard), 'other •••• 12 · 01/2030');
  });
}

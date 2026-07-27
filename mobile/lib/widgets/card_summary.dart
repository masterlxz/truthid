import '../services/vault_repository.dart';

// Extraído de `vault_screen.dart` (_VaultEntryCard) na Fase 15.4, fatia 2 —
// reaproveitado pelo novo `AutofillCreditCardApprovalScreen` (picker de
// cartões), mesmo padrão de `address_summary.dart` na fatia 1. Mantém as
// mesmas strings exatas de antes (refactor puro, `vault_screen_test.dart`
// não pode quebrar). `cardSubtitle` já mascara o número (só os últimos 4
// dígitos) — seguro o bastante pra aparecer numa lista/picker, ao contrário
// do CVV/número completo (nunca expostos fora da tela de confirmação).

String cardTitle(CreditCardData card) => card.label;

String _last4(String cardNumber) => cardNumber.length >= 4
    ? cardNumber.substring(cardNumber.length - 4)
    : cardNumber;

String cardSubtitle(CreditCardData card) =>
    '${card.cardNetwork.name} •••• ${_last4(card.cardNumber)} · ${card.expiryMonth}/${card.expiryYear}';

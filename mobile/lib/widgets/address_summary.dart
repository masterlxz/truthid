import '../services/vault_repository.dart';

// Extraído de `vault_screen.dart` (_VaultEntryCard) na Fase 15.4 — reaproveitado
// pelo novo `AutofillAddressApprovalScreen` (picker de endereços). Mantém as
// mesmas strings exatas de antes (refactor puro, `vault_screen_test.dart`
// não pode quebrar).

String addressTitle(AddressData address) => address.label;

String addressSubtitle(AddressData address) =>
    '${address.street}, ${address.number} · ${address.city}/${address.state} · ${address.zipCode}';

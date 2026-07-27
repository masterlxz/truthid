import type { CreditCardFieldGroup } from './creditCardFieldDetection';
import { setNativeValue } from './fillField';

/**
 * Cartão decifrado, exatamente como `CreditCardData.toJson()` (Mobile,
 * `mobile/lib/services/vault_repository.dart`) o serializa — snake_case,
 * mesma convenção do resto do schema do Vault.
 */
export interface DecryptedCreditCard {
  label: string;
  card_holder_name: string;
  card_number: string;
  expiry_month: string;
  expiry_year: string;
  cvv: string;
  bank?: string | null;
  card_network: string;
}

function setFieldValue(el: HTMLInputElement | HTMLSelectElement, value: string): void {
  if (el instanceof HTMLInputElement) {
    setNativeValue(el, value);
    return;
  }
  el.value = value;
  el.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Preenche o grupo de campos detectado com o cartão decifrado. `expiryYear`
 * é guardado com 4 dígitos no Vault (`AAAA`, ver `vault_entry_form_screen
 * .dart`), mas o campo combinado `cc-exp` ("MM/AA") segue a convenção real
 * de formulário de checkout (2 dígitos) — só o campo separado
 * `expiryYear`/`cc-exp-year` recebe o ano completo, sem normalizar.
 */
export function fillCreditCardGroup(
  group: CreditCardFieldGroup,
  card: DecryptedCreditCard,
): void {
  const { fields } = group;
  if (fields.cardHolderName) setFieldValue(fields.cardHolderName, card.card_holder_name);
  if (fields.cardNumber) setFieldValue(fields.cardNumber, card.card_number);
  if (fields.expiryDate) {
    const shortYear = card.expiry_year.slice(-2);
    setFieldValue(fields.expiryDate, `${card.expiry_month}/${shortYear}`);
  }
  if (fields.expiryMonth) setFieldValue(fields.expiryMonth, card.expiry_month);
  if (fields.expiryYear) setFieldValue(fields.expiryYear, card.expiry_year);
  if (fields.cvv) setFieldValue(fields.cvv, card.cvv);
}

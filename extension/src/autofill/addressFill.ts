import type { AddressFieldGroup } from './addressFieldDetection';
import { setNativeValue } from './fillField';

/**
 * Endereço decifrado, exatamente como `AddressData.toJson()` (Mobile,
 * `mobile/lib/services/vault_repository.dart`) o serializa — snake_case,
 * mesma convenção do resto do schema do Vault.
 */
export interface DecryptedAddress {
  full_name: string;
  street: string;
  number: string;
  complement?: string | null;
  neighborhood: string;
  city: string;
  state: string;
  zip_code: string;
  country: string;
  phone?: string | null;
}

function setFieldValue(el: HTMLInputElement | HTMLSelectElement, value: string): void {
  if (el instanceof HTMLInputElement) {
    setNativeValue(el, value);
    return;
  }
  // `<select>` (ex: campo de estado/país) não precisa do truque de setter
  // nativo — atribuição direta + evento `change` já é o suficiente pra
  // qualquer framework detectar a mudança.
  el.value = value;
  el.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Preenche o grupo de campos detectado com o endereço decifrado. Não há
 * token HTML padrão pra "número"/"bairro" (`AddressFieldKind` não os
 * inclui, ver `addressFieldDetection.ts`) — o número é embutido no próprio
 * campo de rua (`"{street}, {number}"`, convenção comum de formulário
 * ocidental), e "bairro" fica de fora do preenchimento nesta fatia
 * (best-effort, não bloqueante).
 */
export function fillAddressGroup(group: AddressFieldGroup, address: DecryptedAddress): void {
  const { fields } = group;
  if (fields.fullName) setFieldValue(fields.fullName, address.full_name);
  if (fields.street) {
    setFieldValue(
      fields.street,
      address.number ? `${address.street}, ${address.number}` : address.street,
    );
  }
  if (fields.complement && address.complement) setFieldValue(fields.complement, address.complement);
  if (fields.city) setFieldValue(fields.city, address.city);
  if (fields.state) setFieldValue(fields.state, address.state);
  if (fields.zipCode) setFieldValue(fields.zipCode, address.zip_code);
  if (fields.country) setFieldValue(fields.country, address.country);
  if (fields.phone && address.phone) setFieldValue(fields.phone, address.phone);
}

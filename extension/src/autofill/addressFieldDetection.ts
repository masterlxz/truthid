import { findScope, isVisible } from './formDetection';

/**
 * Detecção de campos de endereço (Fase 15.4, fatia 1) — mesmo padrão
 * estrutural de `formDetection.ts` (varredura por `autocomplete`, dedupe via
 * `WeakSet`, agrupamento por `findScope`), mas os tokens não são de login e
 * sim os do vocabulário WHATWG de autocomplete pra endereço
 * (https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill).
 *
 * Nem todo campo do schema `AddressData` (`mobile/lib/services/
 * vault_repository.dart`) tem um token HTML padrão equivalente — não existe
 * "bairro" nem "número" separados no vocabulário WHATWG (a maioria dos
 * formulários ocidentais junta os dois em `address-line1`). Best-effort:
 * mapeia o que dá, deixa os campos sem token batendo de fora do
 * preenchimento (não é bloqueante — `addressFill.ts` só preenche o que
 * encontrar no grupo).
 */
export type AddressFieldKind =
  | 'fullName'
  | 'street'
  | 'complement'
  | 'city'
  | 'state'
  | 'zipCode'
  | 'country'
  | 'phone';

const AUTOCOMPLETE_TOKEN_MAP: Record<string, AddressFieldKind> = {
  name: 'fullName',
  'street-address': 'street',
  'address-line1': 'street',
  'address-line2': 'complement',
  'address-line3': 'complement',
  'address-level2': 'city', // cidade
  'address-level1': 'state', // estado/província
  'postal-code': 'zipCode',
  country: 'country',
  'country-name': 'country',
  tel: 'phone',
  'tel-national': 'phone',
};

export interface AddressFieldGroup {
  scope: ParentNode;
  fields: Partial<Record<AddressFieldKind, HTMLInputElement | HTMLSelectElement>>;
}

// Campos já processados nesta carga de página — mesmo motivo do
// `processedPasswordFields` em `formDetection.ts` (evita reprocessar quando
// o MutationObserver dispara de novo pro mesmo campo).
const processedAddressFields = new WeakSet<HTMLElement>();

// `autocomplete` pode vir com hints extras antes do token principal (ex:
// "shipping address-line1", "section-billing postal-code") — o token que
// importa é sempre o último.
function classifyAutocomplete(
  el: HTMLInputElement | HTMLSelectElement,
): AddressFieldKind | null {
  // `getAttribute` em vez da propriedade IDL `.autocomplete` — jsdom (usado
  // nos testes) não implementa o getter IDL pra `HTMLSelectElement`,
  // diferente de navegadores reais; ler o atributo direto funciona nos dois.
  const raw = (el.getAttribute('autocomplete') || '').toLowerCase().trim();
  if (!raw) return null;
  const tokens = raw.split(/\s+/);
  const last = tokens[tokens.length - 1];
  return AUTOCOMPLETE_TOKEN_MAP[last] ?? null;
}

/**
 * Varre `root` por campos de endereço visíveis ainda não processados,
 * agrupados por escopo (form/container). Só devolve grupos com pelo menos 2
 * campos reconhecidos — um único campo isolado (ex: um `<input type=tel>`
 * de newsletter) não é sinal confiável de formulário de endereço.
 */
export function findAddressFieldGroups(root: ParentNode = document): AddressFieldGroup[] {
  const candidates = Array.from(root.querySelectorAll('input, select')) as Array<
    HTMLInputElement | HTMLSelectElement
  >;

  const groups = new Map<ParentNode, AddressFieldGroup>();

  for (const el of candidates) {
    if (!isVisible(el)) continue;
    if (processedAddressFields.has(el)) continue;

    const kind = classifyAutocomplete(el);
    if (!kind) continue;
    processedAddressFields.add(el);

    const scope = findScope(el);
    let group = groups.get(scope);
    if (!group) {
      group = { scope, fields: {} };
      groups.set(scope, group);
    }
    if (!group.fields[kind]) group.fields[kind] = el;
  }

  return Array.from(groups.values()).filter((g) => Object.keys(g.fields).length >= 2);
}

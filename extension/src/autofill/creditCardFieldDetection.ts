import { findScope, isVisible } from './formDetection';

/**
 * Detecção de campos de cartão de crédito (Fase 15.4, fatia 2) — mesmo
 * padrão estrutural de `addressFieldDetection.ts` (varredura por
 * `autocomplete`, dedupe via `WeakSet`, agrupamento por `findScope`), mas os
 * tokens são os do vocabulário WHATWG de pagamento
 * (https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill-field).
 *
 * `cc-exp` (campo único "MM/AA") e `cc-exp-month`/`cc-exp-year` (campos
 * separados) são tratados como `CreditCardFieldKind`s distintos — sites
 * usam os dois padrões, e não dá pra normalizar na detecção sem já saber
 * qual formato o formulário quer (`creditCardFill.ts` decide o texto certo
 * pra cada um). `cc-type` (bandeira) não tem `CreditCardFieldKind`
 * equivalente — a maioria dos formulários infere a bandeira do próprio
 * número digitado, não pede como campo separado.
 */
export type CreditCardFieldKind =
  | 'cardHolderName'
  | 'cardNumber'
  | 'expiryDate'
  | 'expiryMonth'
  | 'expiryYear'
  | 'cvv';

const AUTOCOMPLETE_TOKEN_MAP: Record<string, CreditCardFieldKind> = {
  'cc-name': 'cardHolderName',
  'cc-number': 'cardNumber',
  'cc-exp': 'expiryDate',
  'cc-exp-month': 'expiryMonth',
  'cc-exp-year': 'expiryYear',
  'cc-csc': 'cvv',
};

export interface CreditCardFieldGroup {
  scope: ParentNode;
  fields: Partial<Record<CreditCardFieldKind, HTMLInputElement | HTMLSelectElement>>;
}

// Campos já processados nesta carga de página — mesmo motivo de
// `processedAddressFields` em `addressFieldDetection.ts`.
const processedCreditCardFields = new WeakSet<HTMLElement>();

// Mesma lógica de `classifyAutocomplete` de `addressFieldDetection.ts`: o
// token que importa é sempre o último (hints de contexto, ex: "billing
// cc-number", vêm antes).
function classifyAutocomplete(
  el: HTMLInputElement | HTMLSelectElement,
): CreditCardFieldKind | null {
  const raw = (el.getAttribute('autocomplete') || '').toLowerCase().trim();
  if (!raw) return null;
  const tokens = raw.split(/\s+/);
  const last = tokens[tokens.length - 1];
  return AUTOCOMPLETE_TOKEN_MAP[last] ?? null;
}

/**
 * Varre `root` por campos de cartão visíveis ainda não processados,
 * agrupados por escopo (form/container). Só devolve grupos com pelo menos 2
 * campos reconhecidos — mesmo limiar de `findAddressFieldGroups`, evita
 * disparar num único campo isolado sem sinal confiável de checkout.
 */
export function findCreditCardFieldGroups(root: ParentNode = document): CreditCardFieldGroup[] {
  const candidates = Array.from(root.querySelectorAll('input, select')) as Array<
    HTMLInputElement | HTMLSelectElement
  >;

  const groups = new Map<ParentNode, CreditCardFieldGroup>();

  for (const el of candidates) {
    if (!isVisible(el)) continue;
    if (processedCreditCardFields.has(el)) continue;

    const kind = classifyAutocomplete(el);
    if (!kind) continue;
    processedCreditCardFields.add(el);

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

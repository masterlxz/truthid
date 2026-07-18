export interface LoginFieldPair {
  passwordField: HTMLInputElement;
  usernameField: HTMLInputElement | null;
}

// Campos de senha já processados nesta carga de página — evita reprocessar
// (e mostrar um ícone duplicado) quando o MutationObserver dispara de novo
// pro mesmo campo. Um WeakSet não impede o GC de coletar o elemento se ele
// sumir do DOM.
const processedPasswordFields = new WeakSet<HTMLInputElement>();

// Usa estilo computado em vez de `offsetParent` (que é sempre `null` em
// jsdom, já que não há motor de layout de verdade — tornaria este código
// impossível de testar) — também funciona em qualquer navegador real e já
// cobre o caso comum de campo escondido (`display:none`/`visibility:hidden`/
// atributo `hidden`), só não pega truques mais elaborados de honeypot
// (ex: `opacity:0` fora da tela), aceitável nesta primeira fatia.
function isVisible(el: HTMLElement): boolean {
  if (el.hidden) return false;
  const style = getComputedStyle(el);
  return style.display !== 'none' && style.visibility !== 'hidden';
}

function isUsernameCandidateType(input: HTMLInputElement): boolean {
  const type = (input.getAttribute('type') || 'text').toLowerCase();
  return type === 'text' || type === 'email' || type === 'tel';
}

function looksLikeUsernameField(input: HTMLInputElement): boolean {
  const autocomplete = (input.autocomplete || '').toLowerCase();
  if (autocomplete.includes('username') || autocomplete.includes('email')) return true;
  return isUsernameCandidateType(input);
}

// Sobe até o `<form>` ancestral mais próximo; sem `<form>` (comum em SPAs
// que não usam a tag semântica), sobe um número fixo de níveis procurando
// um container que já tenha pelo menos 2 campos de texto — bom o bastante
// pra não precisar percorrer o documento inteiro.
function findScope(passwordField: HTMLInputElement): ParentNode {
  const form = passwordField.closest('form');
  if (form) return form;

  let el: HTMLElement | null = passwordField.parentElement;
  for (let depth = 0; depth < 5 && el; depth++) {
    if (el.querySelectorAll('input').length >= 2) return el;
    el = el.parentElement;
  }
  return passwordField.parentElement ?? passwordField.ownerDocument;
}

function findUsernameField(
  passwordField: HTMLInputElement,
  scope: ParentNode,
): HTMLInputElement | null {
  const inputs = Array.from(scope.querySelectorAll('input')) as HTMLInputElement[];
  const passwordIndex = inputs.indexOf(passwordField);
  if (passwordIndex === -1) return null;

  // Procura pra trás a partir do campo de senha — o campo de usuário quase
  // sempre vem imediatamente antes dele na ordem do DOM.
  for (let i = passwordIndex - 1; i >= 0; i--) {
    const candidate = inputs[i];
    if (!isVisible(candidate)) continue;
    if (looksLikeUsernameField(candidate)) return candidate;
  }
  return null;
}

/**
 * Varre `root` por campos de senha visíveis ainda não processados, e pra
 * cada um tenta achar o campo de usuário correspondente (pode ser `null`
 * se não achar nenhum candidato razoável — o autofill ainda preenche só a
 * senha nesse caso).
 */
export function findLoginFieldPairs(root: ParentNode = document): LoginFieldPair[] {
  const passwordFields = Array.from(
    root.querySelectorAll('input[type="password"]'),
  ) as HTMLInputElement[];

  const pairs: LoginFieldPair[] = [];
  for (const passwordField of passwordFields) {
    if (!isVisible(passwordField)) continue;
    if (processedPasswordFields.has(passwordField)) continue;
    processedPasswordFields.add(passwordField);

    const scope = findScope(passwordField);
    pairs.push({ passwordField, usernameField: findUsernameField(passwordField, scope) });
  }
  return pairs;
}

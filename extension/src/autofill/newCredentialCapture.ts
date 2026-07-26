import type { VaultEntry } from '../session/sessionState';
import { findScope } from './formDetection';
import { GET_MATCHING_ENTRIES_MESSAGE, VAULT_EDIT_ENQUEUE_MESSAGE } from './messages';

// Formulários já com um listener de submit anexado — evita escutar duas
// vezes o mesmo formulário (cadastro com senha+confirmar-senha tem 2
// `input[type="password"]`, e `findLoginFieldPairs` devolve um par pra cada
// um; sem essa guarda, um único submit geraria 2 propostas).
const capturedScopes = new WeakSet<ParentNode>();

// Dedupe por carga de página — evita propor de novo a cada tentativa de
// submit pro mesmo site+usuário (ex: usuário errou a senha e tentou de
// novo). Reseta sozinho a cada reload, aceitável (mesmo espírito do
// `processedPasswordFields` de formDetection.ts).
const proposedThisPageLoad = new Set<string>();

async function hasExistingMatch(hostname: string, username: string): Promise<boolean> {
  try {
    const response = await chrome.runtime.sendMessage({
      type: GET_MATCHING_ENTRIES_MESSAGE,
      hostname,
    });
    const entries = (response?.entries as VaultEntry[] | undefined) ?? [];
    return entries.some((entry) => entry.username === username);
  } catch {
    // Sem service worker vivo pra responder, ou nenhuma sessão — não propõe
    // (mesmo silêncio-é-melhor-que-ruído de attachAutofillIconIfMatches).
    return true;
  }
}

async function proposeIfNew(username: string, password: string): Promise<void> {
  if (!password) return;

  const hostname = location.hostname;
  const dedupeKey = `${hostname}:${username}`;
  if (proposedThisPageLoad.has(dedupeKey)) return;

  if (await hasExistingMatch(hostname, username)) return;
  proposedThisPageLoad.add(dedupeKey);

  void chrome.runtime.sendMessage({
    type: VAULT_EDIT_ENQUEUE_MESSAGE,
    proposal: {
      site: hostname,
      url: location.origin,
      username,
      password,
      notes: '',
    },
  });
}

/**
 * Escuta o submit do formulário de um par usuário/senha e propõe a
 * credencial pro Device aprovar, se ainda não estiver salva no Vault —
 * espelha o "Salvar senha?" nativo dos navegadores (dispara na intenção de
 * submit, não na confirmação de sucesso; quem decide de verdade é o Device
 * na tela de aprovação, que mostra site/usuário/senha antes de persistir).
 */
export function attachNewCredentialCapture(
  passwordField: HTMLInputElement,
  usernameField: HTMLInputElement | null,
): void {
  const scope = findScope(passwordField);
  if (capturedScopes.has(scope)) return;
  capturedScopes.add(scope);

  // findScope() tem um fallback pra SPAs sem <form> semântico (sobe até um
  // container com ≥2 inputs), mas 'submit' só dispara de verdade num
  // <form> — sem um, não há sinal confiável de "usuário terminou de
  // preencher" pra capturar aqui. Fora de escopo desta rodada.
  if (!(scope instanceof HTMLFormElement)) return;

  scope.addEventListener('submit', () => {
    const password = passwordField.value;
    const username = usernameField?.value ?? '';
    void proposeIfNew(username, password);
  });
}

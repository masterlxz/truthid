import { findLoginFieldPairs } from '../src/autofill/formDetection';
import { attachAutofillIconIfMatches } from '../src/autofill/overlay';

// Primeiro content script do projeto — detecta formulários de login em
// qualquer página HTTP/HTTPS e oferece preencher usuário/senha a partir do
// vault (nunca o código 2FA: `totp_secret` não existe em `VaultEntry` na
// extensão, de propósito — ver sessionState.ts). Roda no isolated world
// padrão de content script MV3: não precisa de bridge de main-world (isso
// só seria necessário pra interceptar `navigator.credentials`/WebAuthn,
// fora de escopo aqui).
export default defineContentScript({
  matches: ['http://*/*', 'https://*/*'],
  main() {
    function scan(root: ParentNode): void {
      for (const { passwordField, usernameField } of findLoginFieldPairs(root)) {
        void attachAutofillIconIfMatches(passwordField, usernameField);
      }
    }

    scan(document);

    // Cobre formulários renderizados depois do carregamento inicial (SPAs
    // React/Vue/etc. costumam montar o formulário de login de forma
    // assíncrona, não presente no HTML inicial). Debounce simples evita
    // reprocessar em rajada quando várias mutações chegam juntas.
    let debounceHandle: ReturnType<typeof setTimeout> | null = null;
    const observer = new MutationObserver(() => {
      if (debounceHandle) clearTimeout(debounceHandle);
      debounceHandle = setTimeout(() => scan(document), 300);
    });
    observer.observe(document.body, { childList: true, subtree: true });
  },
});

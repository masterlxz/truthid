// Só constantes de mensagem — sem código de DOM — pra background.ts poder
// importar sem puxar junto a lógica de UI de overlay.ts (que só faz
// sentido no contexto de content script).
export const GET_MATCHING_ENTRIES_MESSAGE = 'truthid-get-matching-entries';

// Canal de login com passkey (Sessão 132) — dois passos de propósito: 1)
// pergunta se há passkey pro hostname (sem assinar, decide se mostra o
// prompt de confirmação); 2) só assina depois do clique de aprovação. Mesmo
// motivo de arquivo do GET_MATCHING_ENTRIES_MESSAGE acima — background.ts e
// os content scripts de webauthn.content.ts/webauthn-bridge.content.ts
// importam só isso, sem puxar `webauthn.ts` (crypto) nem UI junto.
export const WEBAUTHN_FIND_PASSKEY_MESSAGE = 'truthid-webauthn-find-passkey';
export const WEBAUTHN_SIGN_ASSERTION_MESSAGE = 'truthid-webauthn-sign-assertion';

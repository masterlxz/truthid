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

// Enfileira uma proposta de credencial nova (Sessão 134/135, item 6 do
// roadmap) — fire-and-forget, igual ao canal acima. Precisa passar pelo
// background porque `chrome.storage.session` não é acessível direto de um
// content script no Brave ("Access to storage is not allowed from this
// context", achado real na validação em hardware da Sessão 135) — mesmo
// motivo pelo qual GET_MATCHING_ENTRIES_MESSAGE já existe: "só o background
// lê/escreve chrome.storage.session".
export const VAULT_EDIT_ENQUEUE_MESSAGE = 'truthid-vault-edit-enqueue';

// Fase 15.4, fatia 1 (autofill de endereço) — o content script não pode
// chamar `chrome.permissions`/`chrome.system.*` direto, mesmo motivo de
// `chrome.storage.session` acima: precisa passar pelo background. Nomes
// genéricos (não "ADDRESS") desde a fatia 2 (cartão de crédito) — o
// transporte (permissão de host, sweep de LAN, fetch manual por IP) nunca
// olhou o conteúdo do pedido, só o `sessionId`; batizar por tipo de dado
// teria forçado 3 handlers idênticos a mais em `background.ts` por tipo
// novo, em vez de 1 handler reusado por todos.
export const AUTOFILL_ENSURE_HOST_PERMISSION_MESSAGE =
  'truthid-autofill-ensure-host-permission';
export const AUTOFILL_SWEEP_MESSAGE = 'truthid-autofill-sweep';
export const AUTOFILL_MANUAL_FETCH_MESSAGE = 'truthid-autofill-manual-fetch';

// Fase 15.4, fatia 2 (dead-drop) — mesma ideia genérica dos 3 canais acima,
// mas pro caminho cross-network (IPFS/IPNS) em vez de LAN. `_START` é
// content script → background (pede pra começar a rastrear um `sessionId`);
// `_RESOLVED` é o inverso, um broadcast do background pra qualquer frame da
// extensão (sem `tabId` — igual `DEAD_DROP_RESOLVED_MESSAGE` já faz pro
// vault-session), já que o content script certo filtra pelo `sessionId` que
// já está esperando.
export const AUTOFILL_START_DEAD_DROP_POLL_MESSAGE = 'truthid-autofill-start-dead-drop-poll';
export const AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE = 'truthid-autofill-dead-drop-resolved';

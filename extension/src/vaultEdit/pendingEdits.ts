import type { Passkey } from '../session/sessionState';

// Fila de propostas de credencial nova, geradas pela extensão a partir de
// `navigator.credentials.create()` interceptado num site real (Sessão 134,
// item 6 do roadmap). Vive em `chrome.storage.session` — chave própria,
// separada da sessão de leitura do vault (`truthid_vault_session`), efêmera
// (nunca gravada em disco, some quando o navegador fecha ou a extensão é
// recarregada). A extensão nunca tem autoridade de escrita no Vault: cada
// proposta aqui só vira uma entrada de verdade depois que um Device
// (Desktop ou Mobile) aprova via /truthid/v1/vault-edit ou QR+LAN.
//
// ⚠️ NUNCA importe este módulo de um content script (entrypoints/*.content.ts)
// — `chrome.storage.session` não é acessível nesse contexto no Brave
// ("Access to storage is not allowed from this context", achado real,
// Sessão 135: era chamado direto de `webauthn-bridge.content.ts` e falhava
// silenciosamente, nenhuma proposta era enfileirada). Content scripts devem
// mandar `chrome.runtime.sendMessage({ type: VAULT_EDIT_ENQUEUE_MESSAGE, ... })`
// pro background (único contexto com storage liberado) chamar `addPendingEdit`
// por eles — ver `entrypoints/background.ts` e `entrypoints/webauthn-bridge.
// content.ts`. `listPendingEdits`/`removePendingEdit` são seguros só em
// contextos de extensão de verdade (popup, background) — nunca em content
// script. O projeto não tem ESLint configurado pra uma regra de
// import-boundary automática; este comentário é a única barreira.
const STORAGE_KEY = 'truthid_pending_vault_edits';

export interface VaultEditProposal {
  id: string; // id local da proposta em si (não da futura VaultEntry — o Device decide esse)
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  passkey?: Passkey;
  createdAtMs: number;
}

async function loadAll(): Promise<VaultEditProposal[]> {
  const result = await chrome.storage.session.get(STORAGE_KEY);
  return (result[STORAGE_KEY] as VaultEditProposal[] | undefined) ?? [];
}

async function saveAll(proposals: VaultEditProposal[]): Promise<void> {
  await chrome.storage.session.set({ [STORAGE_KEY]: proposals });
}

export async function listPendingEdits(): Promise<VaultEditProposal[]> {
  return loadAll();
}

export async function addPendingEdit(
  entry: Omit<VaultEditProposal, 'id' | 'createdAtMs'>,
): Promise<VaultEditProposal> {
  const proposal: VaultEditProposal = {
    ...entry,
    id: crypto.randomUUID(),
    createdAtMs: Date.now(),
  };
  const proposals = await loadAll();
  proposals.push(proposal);
  await saveAll(proposals);
  return proposal;
}

export async function removePendingEdit(id: string): Promise<void> {
  const proposals = await loadAll();
  await saveAll(proposals.filter((p) => p.id !== id));
}

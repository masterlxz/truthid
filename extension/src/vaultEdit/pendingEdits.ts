import type { Passkey } from '../session/sessionState';

// Fila de propostas de credencial nova, geradas pela extensão a partir de
// `navigator.credentials.create()` interceptado num site real (Sessão 134,
// item 6 do roadmap). Vive em `chrome.storage.session` — chave própria,
// separada da sessão de leitura do vault (`truthid_vault_session`), efêmera
// (nunca gravada em disco, some quando o navegador fecha ou a extensão é
// recarregada). A extensão nunca tem autoridade de escrita no Vault: cada
// proposta aqui só vira uma entrada de verdade depois que um Device
// (Desktop ou Mobile) aprova via /truthid/v1/vault-edit ou QR+LAN.
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

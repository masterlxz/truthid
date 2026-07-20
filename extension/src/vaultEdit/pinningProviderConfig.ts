// Config do provider de pinning IPFS usado só pro dead-drop cross-network
// do vault-edit (item 6 do backlog, `deadDropPublish.ts`). Diferente de
// `pendingEdits.ts`/`sessionState.ts` (efêmeros, `chrome.storage.session`),
// isso precisa sobreviver o navegador fechar — usa `chrome.storage.local`.
//
// Minimalista de propósito: só 1 endpoint Kubo, sem a lista multi-provider
// nem o conceito de PSA do Mobile/Desktop (`pinning_provider_service.dart`)
// — a extensão só precisa de 1 nó pra publish, não de redundância de
// pinning. Sem endpoint configurado, `deadDropPublish.publishDeadDrop`
// simplesmente não faz nada (best-effort, mesma postura do Mobile quando
// não há provider Kubo configurado).
const STORAGE_KEY = 'truthid_vault_edit_pinning_provider';

export interface PinningProviderConfig {
  kuboEndpointUrl: string;
}

export async function loadPinningProviderConfig(): Promise<PinningProviderConfig | null> {
  const result = await chrome.storage.local.get(STORAGE_KEY);
  const config = result[STORAGE_KEY] as PinningProviderConfig | undefined;
  if (!config?.kuboEndpointUrl) return null;
  return config;
}

export async function savePinningProviderConfig(kuboEndpointUrl: string): Promise<void> {
  const trimmed = kuboEndpointUrl.trim();
  if (!trimmed) {
    await chrome.storage.local.remove(STORAGE_KEY);
    return;
  }
  await chrome.storage.local.set({ [STORAGE_KEY]: { kuboEndpointUrl: trimmed } });
}

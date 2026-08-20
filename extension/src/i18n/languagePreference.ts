// Preferência manual de idioma do popup — precisa sobreviver o navegador
// fechar, mesmo padrão de `chrome.storage.local` já usado em
// `vaultEdit/pinningProviderConfig.ts`. Sem preferência salva, o idioma
// ativo é resolvido por `detectDefaultLanguage()` (loader.ts), a partir do
// idioma do navegador — mesmo comportamento de antes deste seletor existir.
const STORAGE_KEY = 'truthid_language';

export async function loadLanguagePreference(): Promise<string | null> {
  const result = await chrome.storage.local.get(STORAGE_KEY);
  return (result[STORAGE_KEY] as string | undefined) ?? null;
}

export async function saveLanguagePreference(code: string): Promise<void> {
  await chrome.storage.local.set({ [STORAGE_KEY]: code });
}

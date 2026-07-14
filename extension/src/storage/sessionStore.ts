import type { SessionState } from '../session/sessionState';

/**
 * Wrapper fino sobre `chrome.storage.session` — em-memória, nunca gravado em
 * disco, sobrevive à suspensão do service worker MV3 (ao contrário de uma
 * variável de módulo comum, que se perde quando o worker é suspenso por
 * inatividade). É onde a chave privada efêmera e as entradas decifradas
 * vivem enquanto a sessão dura.
 */
const STORAGE_KEY = 'truthid_vault_session';

export async function saveSession(state: SessionState): Promise<void> {
  await chrome.storage.session.set({ [STORAGE_KEY]: state });
}

export async function loadSession(): Promise<SessionState | null> {
  const result = await chrome.storage.session.get(STORAGE_KEY);
  return (result[STORAGE_KEY] as SessionState | undefined) ?? null;
}

export async function clearSession(): Promise<void> {
  await chrome.storage.session.remove(STORAGE_KEY);
}

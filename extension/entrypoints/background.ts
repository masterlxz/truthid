import { decrypt } from '../src/crypto/ecies';
import { tryFetchDeadDrop } from '../src/session/deadDropPolling';
import type { VaultEntry } from '../src/session/sessionState';
import { isExpired } from '../src/session/sessionState';
import { clearSession, loadSession, saveSession } from '../src/storage/sessionStore';
import { hexToBytes } from '../src/util/bytes';

// Único job do service worker: garantir que a sessão some do
// `chrome.storage.session` quando o TTL expira, mesmo que a popup nunca
// tenha sido reaberta pra checar `expiresAt` sozinha (belt-and-suspenders —
// a popup também checa expiração toda vez que renderiza).
export const SESSION_EXPIRY_ALARM = 'truthid-vault-session-expiry';

// 13.9, fatia 2b: polling do dead-drop roda aqui, não na popup — a popup
// fecha ao perder foco (troca de aba, clique fora), e a propagação de IPNS
// pode levar até ~1-2min. `chrome.alarms` sobrevive à popup fechada e à
// suspensão do service worker (ao contrário de `setInterval`/variável de
// módulo comum). Período mínimo prático de alarmes em produção é ~1min —
// dado que a própria propagação de IPNS já opera nessa escala de tempo,
// isso não é uma limitação real.
export const DEAD_DROP_POLL_ALARM = 'truthid-dead-drop-poll';
export const START_DEAD_DROP_POLL_MESSAGE = 'truthid-start-dead-drop-poll';
export const DEAD_DROP_RESOLVED_MESSAGE = 'truthid-dead-drop-resolved';

// Lê a sessão atual do storage (sempre a verdade corrente — só existe 1
// sessão por vez; criar uma sessão nova substitui a anterior, "cancelando"
// o polling dela sem lógica extra) e tenta resolver o dead-drop 1 vez. Não
// lança: erro de rede ou nome ainda não propagado tentam de novo no próximo
// alarme.
async function pollDeadDropOnce(): Promise<void> {
  const session = await loadSession();
  if (!session || session.status === 'received' || isExpired(session)) {
    chrome.alarms.clear(DEAD_DROP_POLL_ALARM);
    return;
  }

  const blob = await tryFetchDeadDrop(session.sessionId);
  if (!blob) return;

  try {
    const priv = hexToBytes(session.ephemeralPrivateKeyHex);
    const plaintext = await decrypt(blob, priv);
    const entries = JSON.parse(new TextDecoder().decode(plaintext)) as VaultEntry[];

    await saveSession({ ...session, status: 'received', entries });
    chrome.alarms.clear(DEAD_DROP_POLL_ALARM);
    // Best-effort: só pra popup atualizar ao vivo se estiver aberta. Não é
    // necessário pra correção — `init()` na popup já mostra `entries` do
    // storage se `status === 'received'` na próxima vez que abrir.
    void chrome.runtime.sendMessage({ type: DEAD_DROP_RESOLVED_MESSAGE }).catch(() => {});
  } catch {
    // Blob achado mas não decifrou (ex: veio de outra sessão por engano,
    // corrupção) — não trava o alarme, tenta de novo no próximo tick.
  }
}

export default defineBackground(() => {
  chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === SESSION_EXPIRY_ALARM) {
      void clearSession();
      return;
    }
    if (alarm.name === DEAD_DROP_POLL_ALARM) {
      void pollDeadDropOnce();
    }
  });

  chrome.runtime.onMessage.addListener((message: { type?: string } | undefined) => {
    if (message?.type !== START_DEAD_DROP_POLL_MESSAGE) return;
    chrome.alarms.create(DEAD_DROP_POLL_ALARM, { delayInMinutes: 1, periodInMinutes: 1 });
    void pollDeadDropOnce();
  });
});

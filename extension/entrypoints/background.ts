import { decrypt } from '../src/crypto/ecies';
import { matchesOrigin, matchesRpId } from '../src/session/entryMatching';
import { tryFetchDeadDrop } from '../src/session/deadDropPolling';
import type { VaultEntry } from '../src/session/sessionState';
import { isExpired } from '../src/session/sessionState';
import { clearSession, loadSession, saveSession } from '../src/storage/sessionStore';
import { hexToBytes } from '../src/util/bytes';
import {
  GET_MATCHING_ENTRIES_MESSAGE,
  VAULT_EDIT_ENQUEUE_MESSAGE,
  WEBAUTHN_FIND_PASSKEY_MESSAGE,
  WEBAUTHN_SIGN_ASSERTION_MESSAGE,
} from '../src/autofill/messages';
import { signAssertion } from '../src/webauthn';
import { addPendingEdit, type VaultEditProposal } from '../src/vaultEdit/pendingEdits';

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

  // Único canal request/response do projeto até agora (o resto das
  // mensagens é fire-and-forget) — o content script de autofill pergunta
  // quais entradas do vault batem com o hostname da página atual. Só o
  // background lê `chrome.storage.session`; o content script nunca acessa
  // o storage diretamente.
  chrome.runtime.onMessage.addListener(
    (message: { type?: string; hostname?: string } | undefined, _sender, sendResponse) => {
      if (message?.type !== GET_MATCHING_ENTRIES_MESSAGE) return;
      void (async () => {
        const session = await loadSession();
        const entries = (session?.entries ?? []).filter((entry: VaultEntry) =>
          matchesOrigin(entry, message.hostname ?? ''),
        );
        sendResponse({ entries });
      })();
      return true; // mantém o canal aberto pro sendResponse assíncrono
    },
  );

  // Login com passkey (Sessão 132) — mesmo padrão do canal acima, em 2
  // passos de propósito (ver comentário em messages.ts): achar sem assinar
  // primeiro, deixa o bridge isolated-world decidir se mostra o prompt de
  // confirmação antes de gastar uma assinatura de verdade.
  chrome.runtime.onMessage.addListener(
    (message: { type?: string; hostname?: string } | undefined, _sender, sendResponse) => {
      if (message?.type !== WEBAUTHN_FIND_PASSKEY_MESSAGE) return;
      void (async () => {
        const session = await loadSession();
        const matches = (session?.entries ?? [])
          .filter((entry) => entry.passkey && matchesRpId(entry.passkey.rp_id, message.hostname ?? ''))
          .map((entry) => ({ entryId: entry.id, rpId: entry.passkey!.rp_id, site: entry.site }));
        sendResponse({ matches });
      })();
      return true;
    },
  );

  chrome.runtime.onMessage.addListener(
    (
      message:
        | { type?: string; entryId?: string; challenge?: number[]; origin?: string }
        | undefined,
      _sender,
      sendResponse,
    ) => {
      if (message?.type !== WEBAUTHN_SIGN_ASSERTION_MESSAGE) return;
      void (async () => {
        const session = await loadSession();
        const entries = session?.entries ?? [];
        const index = entries.findIndex((entry) => entry.id === message.entryId);
        const passkey = index >= 0 ? entries[index].passkey : undefined;
        if (!session || !passkey || !message.challenge || !message.origin) {
          sendResponse({ ok: false, error: 'not-found' });
          return;
        }

        const assertion = signAssertion({
          privateKeyHex: passkey.private_key_hex,
          rpId: passkey.rp_id,
          signCount: passkey.sign_count,
          challenge: Uint8Array.from(message.challenge),
          origin: message.origin,
        });

        // Incrementa só a cópia em memória da sessão (chrome.storage.session)
        // — a extensão nunca escreve de volta no Vault sincronizado (sem
        // autoridade de escrita), mesma limitação que o "Testar assinatura"
        // do Desktop já aceita (também não persiste o signCount novo).
        entries[index] = { ...entries[index], passkey: { ...passkey, sign_count: assertion.newSignCount } };
        await saveSession({ ...session, entries });

        sendResponse({
          ok: true,
          credentialIdB64: passkey.credential_id_b64,
          userHandleB64: passkey.user_handle_b64,
          authenticatorData: Array.from(assertion.authenticatorData),
          clientDataJSON: assertion.clientDataJSON,
          signatureDer: Array.from(assertion.signatureDer),
        });
      })();
      return true;
    },
  );

  // Enfileira uma proposta de credencial nova (Sessão 134/135) — fire-and-
  // forget, sem sendResponse. Precisa passar pelo background porque
  // `chrome.storage.session` não é acessível direto de um content script no
  // Brave (achado real da Sessão 135); mesmo motivo do canal
  // GET_MATCHING_ENTRIES_MESSAGE acima.
  chrome.runtime.onMessage.addListener(
    (message: { type?: string; proposal?: Omit<VaultEditProposal, 'id' | 'createdAtMs'> } | undefined) => {
      if (message?.type !== VAULT_EDIT_ENQUEUE_MESSAGE || !message.proposal) return;
      void addPendingEdit(message.proposal);
    },
  );
});

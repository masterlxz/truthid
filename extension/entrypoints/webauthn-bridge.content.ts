import {
  WEBAUTHN_FIND_PASSKEY_MESSAGE,
  WEBAUTHN_SIGN_ASSERTION_MESSAGE,
} from '../src/autofill/messages';
import { showWebauthnConfirmPrompt } from '../src/webauthnPrompt';

// Companheiro isolated-world de webauthn.content.ts (main-world, Sessão
// 132) — MAIN-world scripts não têm acesso às APIs de extensão
// (chrome.runtime), então tudo que webauthn.content.ts pede vira uma
// mensagem `window.postMessage` até aqui, que fala com o background pelos
// canais normais (mesmo padrão de GET_MATCHING_ENTRIES_MESSAGE já usado
// pelo autofill) e devolve o resultado do mesmo jeito.
const CHANNEL = '__truthid_webauthn__';

interface BridgeRequest {
  channel: typeof CHANNEL;
  direction: 'request';
  requestId: string;
  rpId: string;
  origin: string;
  challenge: Uint8Array;
}

export default defineContentScript({
  matches: ['http://*/*', 'https://*/*'],
  main() {
    window.addEventListener('message', (event) => {
      // `event.source !== window` descarta mensagens de iframes/outras
      // origens — só a própria página (via webauthn.content.ts, mesmo
      // frame) fala nesse canal.
      if (event.source !== window) return;
      const data = event.data as Partial<BridgeRequest> | undefined;
      if (data?.channel !== CHANNEL || data.direction !== 'request') return;
      void handleRequest(data as BridgeRequest);
    });

    function respond(requestId: string, payload: Record<string, unknown>): void {
      window.postMessage(
        { channel: CHANNEL, direction: 'response', requestId, ...payload },
        location.origin,
      );
    }

    async function handleRequest(request: BridgeRequest): Promise<void> {
      let matches: Array<{ entryId: string; rpId: string; site: string }>;
      try {
        const findResponse = await chrome.runtime.sendMessage({
          type: WEBAUTHN_FIND_PASSKEY_MESSAGE,
          hostname: request.rpId,
        });
        matches = findResponse?.matches ?? [];
      } catch {
        // Sem service worker vivo pra responder, ou nenhuma sessão — cai
        // pro fluxo nativo do navegador, igual a "sem match" de propósito.
        respond(request.requestId, { result: 'no-match' });
        return;
      }

      if (matches.length === 0) {
        respond(request.requestId, { result: 'no-match' });
        return;
      }

      // Sempre a primeira que bater — sem UI de escolha entre múltiplas
      // passkeys pro mesmo site nesta fase (nenhum caso real disso ainda;
      // mesma simplificação aceitável do autofill de senha, que só mostra
      // dropdown quando há mais de uma senha).
      const match = matches[0];
      const approved = await showWebauthnConfirmPrompt(match.site || match.rpId);
      if (!approved) {
        respond(request.requestId, { result: 'declined' });
        return;
      }

      try {
        const signResponse = await chrome.runtime.sendMessage({
          type: WEBAUTHN_SIGN_ASSERTION_MESSAGE,
          entryId: match.entryId,
          challenge: Array.from(request.challenge),
          origin: request.origin,
        });
        if (!signResponse?.ok) {
          respond(request.requestId, { result: 'error' });
          return;
        }
        respond(request.requestId, {
          result: 'signed',
          credentialIdB64: signResponse.credentialIdB64,
          userHandleB64: signResponse.userHandleB64,
          authenticatorData: Uint8Array.from(signResponse.authenticatorData as number[]),
          clientDataJSON: signResponse.clientDataJSON,
          signatureDer: Uint8Array.from(signResponse.signatureDer as number[]),
        });
      } catch {
        respond(request.requestId, { result: 'error' });
      }
    }
  },
});

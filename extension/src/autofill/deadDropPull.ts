import {
  AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE,
  AUTOFILL_START_DEAD_DROP_POLL_MESSAGE,
} from './messages';

/**
 * Puxa a resposta cifrada de um pedido de autofill via dead-drop
 * (IPFS/IPNS) — mesma assinatura de `sweepMobileForBlob`/`fetchMobileBlobAt`
 * (`lanPull.ts`), pra caber no mesmo `.then((blob) => { if (blob) void
 * handleBlob(blob); })` que os overlays já usam pro sweep de LAN. Sem
 * `sessionId` guardado em `chrome.storage.session` (a chave privada efêmera
 * vive só no closure do content script que chamou isto) — quem faz o
 * polling de verdade é `background.ts` (só ele tem `chrome.alarms`); esta
 * função só pede pra começar e escuta o resultado.
 */
export function pullFromDeadDrop(sessionId: string, expiresAtMs: number): Promise<string | null> {
  return new Promise((resolve) => {
    let settled = false;

    function finish(blob: string | null): void {
      if (settled) return;
      settled = true;
      chrome.runtime.onMessage.removeListener(listener);
      resolve(blob);
    }

    function listener(message: { type?: string; sessionId?: string; blob?: string } | undefined): void {
      if (message?.type !== AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE) return;
      if (message.sessionId !== sessionId) return;
      finish(message.blob ?? null);
    }

    chrome.runtime.onMessage.addListener(listener);
    void chrome.runtime
      .sendMessage({ type: AUTOFILL_START_DEAD_DROP_POLL_MESSAGE, sessionId, expiresAt: expiresAtMs })
      .catch(() => {});

    // Mesmo TTL do QR (`expiresAtMs`) — sem inventar um timeout novo. Se o
    // background nunca resolver (nome nunca propagou, ou o alarme expirou
    // silenciosamente do lado dele), desiste aqui também.
    setTimeout(() => finish(null), Math.max(0, expiresAtMs - Date.now()));
  });
}

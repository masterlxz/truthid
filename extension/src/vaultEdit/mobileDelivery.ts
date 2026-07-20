import { secp256k1 } from '@noble/curves/secp256k1';

import { bytesToHex } from '../util/bytes';
import { buildVaultEditQrPayload, randomSessionId, type VaultEditQrPayload } from '../session/qrPayload';
import { deriveVaultEditContentKey, encryptVaultEditContent } from './cipher';
import { publishDeadDrop } from './deadDropPublish';
import { MOBILE_CANDIDATE_PORTS, pushToMobile, putSessionContent } from './lanDelivery';
import type { VaultEditProposal } from './pendingEdits';

export interface MobileDeliverySession {
  qrPayload: VaultEditQrPayload;
  /** Varre a LAN e empurra a proposta cifrada — chamar depois de renderizar o QR. */
  send: () => Promise<boolean>;
  /**
   * Empurra pra um host específico (fallback manual quando `send()` não acha
   * ninguém — ex: Brave, que bloqueia `chrome.system.network` e faz a
   * varredura automática de `send()` nunca nem começar, mesmo padrão já
   * resolvido pro fluxo de leitura do vault em `lanDiscovery.ts`/
   * `manual-connect`).
   */
  sendTo: (host: string) => Promise<boolean>;
}

/**
 * Orquestra o caminho "celular via QR" (Sessão 134): gera sessionId +
 * keypair efêmero (o `ephemeralPubKey` entra no QR pra manter o mesmo
 * schema de 5 campos do `/truthid/v1/pin`, mas nenhuma fase de retorno usa
 * a chave privada nesta rodada — ver PROJECT_STATE.md, "fora de escopo"),
 * monta o payload do QR, e devolve um `send()` que cifra a proposta
 * (`cipher.ts`, chave derivada do `sessionId`) e varre a LAN
 * (`lanDelivery.ts`) até algum device aceitar.
 */
export function startMobileDelivery(
  proposal: Omit<VaultEditProposal, 'id' | 'createdAtMs'>,
  deps: {
    push?: typeof pushToMobile;
    putAt?: typeof putSessionContent;
    publish?: typeof publishDeadDrop;
  } = {},
): MobileDeliverySession {
  const push = deps.push ?? pushToMobile;
  const putAt = deps.putAt ?? putSessionContent;
  const publish = deps.publish ?? publishDeadDrop;
  const sessionId = randomSessionId();
  const ephemeralPubKeyHex = bytesToHex(
    secp256k1.getPublicKey(secp256k1.utils.randomPrivateKey(), true),
  );
  const qrPayload = buildVaultEditQrPayload(sessionId, ephemeralPubKeyHex);

  async function encryptedBody(): Promise<Uint8Array> {
    const key = deriveVaultEditContentKey(sessionId);
    const plaintext = new TextEncoder().encode(JSON.stringify(proposal));
    return encryptVaultEditContent(plaintext, key);
  }

  // Dead-drop cross-network (item 6 do backlog): dispara em paralelo com o
  // resto, assim que o QR existe — mesmo timing do Mobile no pareamento de
  // leitura (`vault_session_screen.dart`, publish roda junto com o serve
  // LAN, não depois). Fire-and-forget: `publishDeadDrop` já é best-effort
  // internamente (sem provider configurado ou qualquer falha vira `null`),
  // uma falha aqui não pode atrapalhar `send()`/`sendTo()`.
  void encryptedBody()
    .then((body) => publish(sessionId, body))
    .catch(() => {});

  async function send(): Promise<boolean> {
    return push(sessionId, await encryptedBody());
  }

  async function sendTo(host: string): Promise<boolean> {
    const body = await encryptedBody();
    for (const port of MOBILE_CANDIDATE_PORTS) {
      if (await putAt(host, port, sessionId, body)) return true;
    }
    return false;
  }

  return { qrPayload, send, sendTo };
}

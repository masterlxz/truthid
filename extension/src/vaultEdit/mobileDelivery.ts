import { secp256k1 } from '@noble/curves/secp256k1';

import { VAULT_EDIT_START_DEAD_DROP_PUBLISH_MESSAGE } from '../autofill/messages';
import { bytesToBase64, bytesToHex } from '../util/bytes';
import { buildVaultEditQrPayload, randomSessionId, type VaultEditQrPayload } from '../session/qrPayload';
import { deriveVaultEditContentKey, encryptVaultEditContent } from './cipher';
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
 * a chave privada nesta rodada — ver project/INDEX.md, "fora de escopo"),
 * monta o payload do QR, e devolve um `send()` que cifra as propostas
 * (`cipher.ts`, chave derivada do `sessionId`) e varre a LAN
 * (`lanDelivery.ts`) até algum device aceitar.
 *
 * `proposals` — sync em lote (P29): 1+ propostas viajam juntas numa sessão
 * só. O conteúdo cifrado é sempre uma lista JSON agora (mesmo com 1 item) —
 * o Mobile aceita tanto lista quanto objeto único (back-compat com o SDK
 * Dart, que ainda manda uma proposta por sessão), mas a extensão sempre
 * manda lista desde este ponto em diante.
 */
export function startMobileDelivery(
  proposals: Array<Omit<VaultEditProposal, 'id' | 'createdAtMs'>>,
  deps: {
    push?: typeof pushToMobile;
    putAt?: typeof putSessionContent;
    sendMessage?: typeof chrome.runtime.sendMessage;
  } = {},
): MobileDeliverySession {
  const push = deps.push ?? pushToMobile;
  const putAt = deps.putAt ?? putSessionContent;
  // Acesso opcional (não `chrome.runtime.sendMessage` direto): em teste
  // (`environment: 'node'`, ver vitest.config.ts) `chrome` não existe no
  // global, e `startMobileDelivery` é chamado sem `deps.sendMessage` na
  // maioria dos testes — acessar a propriedade sem `?.` lançaria antes
  // mesmo de qualquer QR ser montado.
  const sendMessage = deps.sendMessage ?? globalThis.chrome?.runtime?.sendMessage;
  const sessionId = randomSessionId();
  const ephemeralPubKeyHex = bytesToHex(
    secp256k1.getPublicKey(secp256k1.utils.randomPrivateKey(), true),
  );
  const qrPayload = buildVaultEditQrPayload(sessionId, ephemeralPubKeyHex);

  async function encryptedBody(): Promise<Uint8Array> {
    const key = deriveVaultEditContentKey(sessionId);
    const plaintext = new TextEncoder().encode(JSON.stringify(proposals));
    return encryptVaultEditContent(plaintext, key);
  }

  // Dead-drop cross-network (item 6 do backlog): dispara em paralelo com o
  // resto, assim que o QR existe — mesmo timing do Mobile no pareamento de
  // leitura (`vault_session_screen.dart`, publish roda junto com o serve
  // LAN, não depois). Delega o publish de verdade pro background via
  // mensagem (achado do /code-review, Sessão 140) em vez de chamar
  // `publishDeadDrop` aqui — a popup fecha assim que o usuário olha pro
  // celular pra escanear o QR, o que abortava a sequência de ~4 fetches
  // (~60-90s) no meio quase sempre; o background sobrevive à popup fechada.
  // Fire-and-forget: `publishDeadDrop` já é best-effort internamente lá
  // dentro (sem provider configurado ou qualquer falha vira `null`), uma
  // falha aqui não pode atrapalhar `send()`/`sendTo()`.
  void encryptedBody()
    .then((body) =>
      sendMessage?.({
        type: VAULT_EDIT_START_DEAD_DROP_PUBLISH_MESSAGE,
        sessionId,
        bodyBase64: bytesToBase64(body),
      }),
    )
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

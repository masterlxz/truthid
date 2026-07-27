import { secp256k1 } from '@noble/curves/secp256k1';

import { decrypt } from '../crypto/ecies';
import { buildAutofillAddressQrPayload, randomSessionId } from '../session/qrPayload';
import { renderQrToCanvas } from '../ui/renderQr';
import { bytesToHex } from '../util/bytes';
import { fillAddressGroup, type DecryptedAddress } from './addressFill';
import type { AddressFieldGroup } from './addressFieldDetection';
import { pullFromDeadDrop } from './deadDropPull';
import { fetchAddressFromDesktop } from './desktopDelivery';
import {
  AUTOFILL_ENSURE_HOST_PERMISSION_MESSAGE,
  AUTOFILL_MANUAL_FETCH_MESSAGE,
  AUTOFILL_SWEEP_MESSAGE,
} from './messages';

// Mesma técnica de Shadow DOM de overlay.ts (senha) — isola do CSS da
// página hospedeira. Painel maior que o dropdown de senha (tem QR canvas +
// input de IP manual), mas os tokens de cor são os mesmos.
const OVERLAY_STYLE = `
  .icon {
    position: fixed;
    width: 22px;
    height: 22px;
    cursor: pointer;
    z-index: 2147483647;
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #111820;
    border: 1px solid #1f2630;
    padding: 0;
  }
  .icon img {
    width: 14px;
    height: 14px;
  }
  .icon:hover {
    border-color: #4dd0e1;
  }
  .panel {
    position: fixed;
    width: 260px;
    background: #111820;
    border: 1px solid #1f2630;
    border-radius: 8px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
    font-family: 'Inter', system-ui, sans-serif;
    font-size: 13px;
    color: #e6edf3;
    z-index: 2147483647;
    padding: 12px;
    box-sizing: border-box;
  }
  .status {
    margin-bottom: 8px;
    line-height: 1.4;
  }
  .panel canvas {
    display: block;
    width: 100%;
    height: auto;
    margin-bottom: 8px;
  }
  .manual-row {
    display: flex;
    gap: 6px;
  }
  .manual-row input {
    flex: 1;
    min-width: 0;
    background: #1f2630;
    border: 1px solid #2a323d;
    border-radius: 4px;
    color: #e6edf3;
    padding: 4px 6px;
    font-size: 12px;
  }
  .manual-row button {
    background: #4dd0e1;
    color: #0b0f14;
    border: none;
    border-radius: 4px;
    padding: 4px 10px;
    cursor: pointer;
    font-size: 12px;
  }
`;

// Um ícone por grupo de campos detectado (não por campo individual) — evita
// mostrar N ícones pro mesmo formulário de endereço.
const processedGroups = new WeakSet<ParentNode>();

/**
 * Ancora um ícone Shadow-DOM ao grupo de campos de endereço detectado
 * (`addressFieldDetection.ts`). Ao clicar, mostra QR + fallback de IP
 * manual, aguarda a resposta cifrada do celular (LAN, fatia 1 — sem
 * dead-drop ainda) e preenche o formulário ao aprovar.
 */
export function attachAddressAutofillIcon(group: AddressFieldGroup): void {
  if (processedGroups.has(group.scope)) return;
  processedGroups.add(group.scope);

  const anchorField =
    group.fields.street ?? group.fields.fullName ?? Object.values(group.fields)[0];
  if (!anchorField) return;

  const host = document.createElement('div');
  document.documentElement.appendChild(host);
  const shadow = host.attachShadow({ mode: 'closed' });

  const style = document.createElement('style');
  style.textContent = OVERLAY_STYLE;
  shadow.appendChild(style);

  const icon = document.createElement('button');
  icon.className = 'icon';
  icon.type = 'button';
  icon.setAttribute('aria-label', 'Fill address with TruthID');
  const iconImg = document.createElement('img');
  iconImg.src = chrome.runtime.getURL('icon/32.png');
  iconImg.alt = '';
  icon.appendChild(iconImg);
  shadow.appendChild(icon);

  function positionIcon(): void {
    const rect = anchorField.getBoundingClientRect();
    icon.style.top = `${rect.top + (rect.height - 22) / 2}px`;
    icon.style.left = `${rect.right - 26}px`;
  }
  positionIcon();
  window.addEventListener('scroll', positionIcon, true);
  window.addEventListener('resize', positionIcon);

  let panel: HTMLElement | null = null;

  function closePanel(): void {
    panel?.remove();
    panel = null;
  }

  async function openPanel(): Promise<void> {
    closePanel();
    panel = document.createElement('div');
    panel.className = 'panel';
    const rect = icon.getBoundingClientRect();
    panel.style.top = `${rect.bottom + 4}px`;
    panel.style.left = `${Math.max(0, rect.right - 260)}px`;
    shadow.appendChild(panel);

    const status = document.createElement('div');
    status.className = 'status';
    status.textContent = 'Checking local network access...';
    panel.appendChild(status);

    let permission: { granted?: boolean } | undefined;
    try {
      permission = await chrome.runtime.sendMessage({
        type: AUTOFILL_ENSURE_HOST_PERMISSION_MESSAGE,
      });
    } catch {
      permission = { granted: false };
    }
    if (!permission?.granted) {
      status.textContent =
        'Open the TruthID extension icon once to grant local network access, then try again.';
      return;
    }

    const sessionId = randomSessionId();
    const privKey = secp256k1.utils.randomPrivateKey();
    const pubKey = secp256k1.getPublicKey(privKey, true);
    const qrPayload = buildAutofillAddressQrPayload(sessionId, `0x${bytesToHex(pubKey)}`);

    status.textContent = 'Scan this QR with your phone to fill this address:';

    const canvas = document.createElement('canvas');
    panel.appendChild(canvas);
    await renderQrToCanvas(canvas, JSON.stringify(qrPayload));

    const manualRow = document.createElement('div');
    manualRow.className = 'manual-row';
    const ipInput = document.createElement('input');
    ipInput.type = 'text';
    ipInput.placeholder = "Phone's IP (if not found automatically)";
    const connectButton = document.createElement('button');
    connectButton.type = 'button';
    connectButton.textContent = 'Connect';
    manualRow.appendChild(ipInput);
    manualRow.appendChild(connectButton);
    panel.appendChild(manualRow);

    let resolved = false;

    // Compartilhado pelos 3 transportes (LAN/dead-drop, que chegam cifrados
    // e passam por handleBlob; Desktop loopback, que chega em claro e chama
    // isto direto) — guarda o `resolved` num único lugar, em vez de repetir
    // o guard em cada um dos 3 call sites. Sem `await` aqui dentro: mesmo
    // que 2 transportes resolvam quase juntos, só a primeira chamada aplica
    // algo (a segunda vê `resolved` true e sai).
    function applyResult(result: { status: string; address?: DecryptedAddress }): void {
      if (resolved) return;
      resolved = true;
      if (result.status === 'filled' && result.address) {
        fillAddressGroup(group, result.address);
        status.textContent = 'Filled ✓';
        setTimeout(closePanel, 1500);
      } else if (result.status === 'no-addresses') {
        status.textContent =
          "You don't have any saved addresses yet — add one in the Vault first.";
      } else {
        status.textContent = 'Request rejected.';
      }
    }

    async function handleBlob(blobB64: string): Promise<void> {
      if (resolved) return;
      try {
        const blobBytes = Uint8Array.from(atob(blobB64), (c) => c.charCodeAt(0));
        const plaintext = await decrypt(blobBytes, privKey);
        const result = JSON.parse(new TextDecoder().decode(plaintext)) as {
          status: string;
          address?: DecryptedAddress;
        };
        applyResult(result);
      } catch {
        if (!resolved) {
          resolved = true;
          status.textContent = 'Received an answer, but could not decrypt it.';
        }
      }
    }

    // Varredura automática — na prática um no-op gracioso na maioria dos
    // navegadores hoje (chrome.system.network não é declarado no manifest,
    // ver wxt.config.ts), mantida por paridade/future-proofing. O fallback
    // de IP manual abaixo é o caminho que realmente funciona.
    void chrome.runtime
      .sendMessage({ type: AUTOFILL_SWEEP_MESSAGE, sessionId })
      .then((response) => {
        const blob = response?.blob as string | undefined;
        if (blob) void handleBlob(blob);
      })
      .catch(() => {});

    // Dead-drop (Fase 15.4, fatia 2) — em paralelo com o LAN acima, nunca
    // como fallback sequencial (mesma decisão já travada na 13.9 fatia
    // 2a/2b: esconder a latência de propagação do IPNS atrás do tempo que o
    // usuário já ia esperar de qualquer forma). O `resolved` guard dentro de
    // `handleBlob` evita processar duas vezes se os dois caminhos resolverem
    // quase juntos.
    void pullFromDeadDrop(sessionId, qrPayload.expiresAt).then((blob) => {
      if (blob) void handleBlob(blob);
    });

    // Desktop loopback (Fase 15.4, fatia 2) — terceira tentativa em
    // paralelo: se o TruthID Desktop estiver rodando na mesma máquina, ele
    // responde direto (sem QR, sem cifra — mesmo nível de confiança do
    // /pin/vault-edit). Chega em claro, não em blob cifrado — vai direto
    // pra applyResult, não passa por handleBlob. `not-found`/`timeout`/
    // `busy`/`invalid`/`error` ficam em silêncio: Desktop não está rodando,
    // ou não é o caminho que resolveu — o LAN/dead-drop (Mobile) ainda
    // podem responder.
    void fetchAddressFromDesktop().then((result) => {
      if (result.status === 'filled' || result.status === 'no-addresses' || result.status === 'rejected') {
        applyResult(result);
      }
    });

    connectButton.addEventListener('click', () => {
      const manualHost = ipInput.value.trim();
      if (!manualHost || resolved) return;
      status.textContent = 'Connecting...';
      void chrome.runtime
        .sendMessage({
          type: AUTOFILL_MANUAL_FETCH_MESSAGE,
          host: manualHost,
          sessionId,
        })
        .then((response) => {
          const blob = response?.blob as string | undefined;
          if (blob) {
            void handleBlob(blob);
          } else if (!resolved) {
            status.textContent = 'No response from that address — check the IP and try again.';
          }
        })
        .catch(() => {
          if (!resolved) {
            status.textContent = 'No response from that address — check the IP and try again.';
          }
        });
    });

    setTimeout(() => {
      if (!resolved) status.textContent = 'This request expired — click the icon to try again.';
    }, Math.max(0, qrPayload.expiresAt - Date.now()));
  }

  icon.addEventListener('click', (event) => {
    event.stopPropagation();
    if (panel) {
      closePanel();
    } else {
      void openPanel();
    }
  });

  document.addEventListener('click', closePanel);
}

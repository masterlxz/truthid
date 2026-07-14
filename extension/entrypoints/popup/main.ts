import { secp256k1 } from '@noble/curves/secp256k1';

import { decrypt } from '../../src/crypto/ecies';
import {
  CANDIDATE_PORTS,
  fetchSessionBlob,
  sweepLan,
} from '../../src/session/lanDiscovery';
import {
  buildQrPayload,
  randomSessionId,
  toQrPayload,
} from '../../src/session/qrPayload';
import type {
  SessionState,
  VaultEntry,
} from '../../src/session/sessionState';
import { isExpired } from '../../src/session/sessionState';
import {
  clearSession,
  loadSession,
  saveSession,
} from '../../src/storage/sessionStore';
import { renderEntries } from '../../src/ui/renderEntries';
import { renderQrToCanvas } from '../../src/ui/renderQr';
import { bytesToHex, hexToBytes } from '../../src/util/bytes';

const SESSION_EXPIRY_ALARM = 'truthid-vault-session-expiry';
const START_DEAD_DROP_POLL_MESSAGE = 'truthid-start-dead-drop-poll';
const DEAD_DROP_RESOLVED_MESSAGE = 'truthid-dead-drop-resolved';
const HOST_PERMISSION: chrome.permissions.Permissions = {
  origins: ['http://*/*'],
};

function base64ToBytes(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

async function createNewSession(): Promise<SessionState> {
  const privKey = secp256k1.utils.randomPrivateKey();
  const pubKey = secp256k1.getPublicKey(privKey, true);
  const sessionId = randomSessionId();
  const payload = buildQrPayload(sessionId, `0x${bytesToHex(pubKey)}`);

  const state: SessionState = {
    status: 'showingQr',
    sessionId,
    ephemeralPrivateKeyHex: bytesToHex(privKey),
    ephemeralPublicKeyHex: payload.ephemeralPubKey,
    expiresAt: payload.expiresAt,
  };
  await saveSession(state);
  chrome.alarms.create(SESSION_EXPIRY_ALARM, { when: state.expiresAt });
  // 13.9, fatia 2b: o dead-drop já começa a ser resolvido em background
  // (chrome.alarms, sobrevive à popup fechada) assim que o QR aparece, sem
  // esperar o usuário clicar em "Find" — esconde a latência de propagação
  // do IPNS atrás do tempo que ele já vai gastar escaneando/escolhendo
  // perfil no celular. Best-effort: se o listener do background não
  // responder por algum motivo, a sessão ainda funciona via LAN normalmente.
  void chrome.runtime.sendMessage({ type: START_DEAD_DROP_POLL_MESSAGE }).catch(() => {});
  return state;
}

const els = {
  qrSection: document.getElementById('qr-section') as HTMLElement,
  qrCanvas: document.getElementById('qr-canvas') as HTMLCanvasElement,
  statusText: document.getElementById('status-text') as HTMLElement,
  findButton: document.getElementById('find-button') as HTMLButtonElement,
  manualIpInput: document.getElementById('manual-ip') as HTMLInputElement,
  manualConnectButton: document.getElementById(
    'manual-connect',
  ) as HTMLButtonElement,
  entriesSection: document.getElementById('entries-section') as HTMLElement,
  entriesList: document.getElementById('entries-list') as HTMLElement,
  newSessionButton: document.getElementById('new-session') as HTMLButtonElement,
  newSessionButton2: document.getElementById(
    'new-session-2',
  ) as HTMLButtonElement,
};

let currentState: SessionState | null = null;

async function showQr(state: SessionState): Promise<void> {
  els.qrSection.hidden = false;
  els.entriesSection.hidden = true;
  els.statusText.textContent =
    'A backup delivery is already trying in the background — click "Find" ' +
    "for a faster local-network delivery once you've scanned the code.";

  const payload = toQrPayload(
    state.sessionId,
    state.ephemeralPublicKeyHex,
    state.expiresAt,
  );
  await renderQrToCanvas(els.qrCanvas, JSON.stringify(payload));
}

function showEntries(entries: VaultEntry[]): void {
  els.qrSection.hidden = true;
  els.entriesSection.hidden = false;
  renderEntries(els.entriesList, entries);
}

// Ponto comum pra "cheguei num blob cifrado, decifra e mostra" — o LAN
// entrega um JSON `{blob: base64}` (ver `handleBlob` abaixo), o dead-drop
// entrega os bytes crus do gateway diretamente (mesmo blob ECIES sem
// nenhum envelope extra — confirmado em `vault_session_screen.dart`, é o
// mesmo `encryptedBlob` usado nos dois transportes).
async function handleBlobBytes(blob: Uint8Array): Promise<void> {
  if (!currentState) return;
  const priv = hexToBytes(currentState.ephemeralPrivateKeyHex);
  const plaintext = await decrypt(blob, priv);
  const entries = JSON.parse(new TextDecoder().decode(plaintext)) as VaultEntry[];

  currentState = { ...currentState, status: 'received', entries };
  await saveSession(currentState);
  showEntries(entries);
}

async function handleBlob(blobBase64: string): Promise<void> {
  await handleBlobBytes(base64ToBytes(blobBase64));
}

// O dead-drop é decifrado dentro do background (não aqui — ver
// `entrypoints/background.ts`, é o que permite resolver mesmo com a popup
// fechada). Esse listener só recarrega o resultado do storage pra
// atualizar a UI ao vivo se a popup estiver aberta no momento — não é
// necessário pra correção: reabrir a popup já mostra as entradas via
// `init()` de qualquer forma.
chrome.runtime.onMessage.addListener((message: { type?: string } | undefined) => {
  if (message?.type !== DEAD_DROP_RESOLVED_MESSAGE) return;
  void (async () => {
    if (!currentState || currentState.status === 'received') return;
    const stored = await loadSession();
    if (stored?.status === 'received' && stored.sessionId === currentState.sessionId && stored.entries) {
      currentState = stored;
      showEntries(stored.entries);
    }
  })();
});

async function ensureHostPermission(): Promise<boolean> {
  const granted = await chrome.permissions.contains(HOST_PERMISSION);
  if (granted) return true;
  return chrome.permissions.request(HOST_PERMISSION);
}

async function init(): Promise<void> {
  const stored = await loadSession();

  if (stored && !isExpired(stored) && stored.status === 'received' && stored.entries) {
    currentState = stored;
    showEntries(stored.entries);
    return;
  }

  if (stored && !isExpired(stored)) {
    currentState = stored;
    await showQr(stored);
    return;
  }

  currentState = await createNewSession();
  await showQr(currentState);
}

els.findButton.addEventListener('click', async () => {
  if (!currentState) return;
  if (isExpired(currentState)) {
    els.statusText.textContent = 'This session expired — generate a new QR code.';
    return;
  }

  els.statusText.textContent = 'Looking for your phone on the local network...';

  // `system.network` só existe em Chrome/Edge — se essa API não estiver
  // disponível (Firefox), sweepLan não acha IPs locais e retorna null sem
  // erro, caindo direto pro fallback manual abaixo.
  const granted = await ensureHostPermission();
  if (!granted) {
    els.statusText.textContent =
      "Permission denied — enter your phone's IP manually below.";
    return;
  }

  const blob = await sweepLan(currentState.sessionId);
  if (blob) {
    await handleBlob(blob);
    return;
  }

  if (currentState.status === 'received') return; // dead-drop já resolveu em background enquanto o sweep rodava

  els.statusText.textContent =
    "Couldn't find your phone automatically. Enter its IP manually below, or " +
    'wait — a backup delivery is still trying in the background (can take a ' +
    'couple of minutes).';
});

els.manualConnectButton.addEventListener('click', async () => {
  if (!currentState) return;
  if (isExpired(currentState)) {
    els.statusText.textContent = 'This session expired — generate a new QR code.';
    return;
  }

  const ip = els.manualIpInput.value.trim();
  if (!ip) return;

  els.statusText.textContent = `Trying ${ip}...`;
  for (const port of CANDIDATE_PORTS) {
    const blob = await fetchSessionBlob(ip, port, currentState.sessionId);
    if (blob) {
      await handleBlob(blob);
      return;
    }
  }
  els.statusText.textContent = "Couldn't reach your phone at that address.";
});

async function startNewSession(): Promise<void> {
  await clearSession();
  currentState = await createNewSession();
  await showQr(currentState);
}

els.newSessionButton.addEventListener('click', () => void startNewSession());
els.newSessionButton2.addEventListener('click', () => void startNewSession());

void init();

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

const SESSION_EXPIRY_ALARM = 'truthid-vault-session-expiry';
const HOST_PERMISSION: chrome.permissions.Permissions = {
  origins: ['http://*/*'],
};

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

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
  els.statusText.textContent = '';

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

async function handleBlob(blobBase64: string): Promise<void> {
  if (!currentState) return;
  const blob = base64ToBytes(blobBase64);
  const priv = hexToBytes(currentState.ephemeralPrivateKeyHex);
  const plaintext = await decrypt(blob, priv);
  const entries = JSON.parse(new TextDecoder().decode(plaintext)) as VaultEntry[];

  currentState = { ...currentState, status: 'received', entries };
  await saveSession(currentState);
  showEntries(entries);
}

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

  els.statusText.textContent =
    "Couldn't find your phone automatically. Enter its IP manually below.";
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

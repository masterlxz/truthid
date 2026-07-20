import { secp256k1 } from '@noble/curves/secp256k1';

import { decrypt } from '../../src/crypto/ecies';
import {
  CANDIDATE_PORTS,
  fetchSessionBlob,
  isNetworkDiscoverySupported,
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
import { listPendingEdits, removePendingEdit, type VaultEditProposal } from '../../src/vaultEdit/pendingEdits';
import { sendToDesktop } from '../../src/vaultEdit/desktopDelivery';
import { startMobileDelivery, type MobileDeliverySession } from '../../src/vaultEdit/mobileDelivery';

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
  pendingEditsSection: document.getElementById('pending-edits-section') as HTMLElement,
  pendingEditsBadge: document.getElementById('pending-edits-badge') as HTMLElement,
  pendingEditsStatus: document.getElementById('pending-edits-status') as HTMLElement,
  sendToDesktopButton: document.getElementById('send-to-desktop') as HTMLButtonElement,
  sendToPhoneButton: document.getElementById('send-to-phone') as HTMLButtonElement,
  pendingEditQrWrapper: document.getElementById('pending-edit-qr-wrapper') as HTMLElement,
  pendingEditQrCanvas: document.getElementById('pending-edit-qr-canvas') as HTMLCanvasElement,
  pendingEditRetryButton: document.getElementById(
    'pending-edit-retry',
  ) as HTMLButtonElement,
  pendingEditManualIpInput: document.getElementById(
    'pending-edit-manual-ip',
  ) as HTMLInputElement,
  pendingEditManualConnectButton: document.getElementById(
    'pending-edit-manual-connect',
  ) as HTMLButtonElement,
};

let currentState: SessionState | null = null;

async function showQr(state: SessionState): Promise<void> {
  els.qrSection.hidden = false;
  els.entriesSection.hidden = true;
  els.statusText.textContent = isNetworkDiscoverySupported()
    ? 'A backup delivery is already trying in the background — click "Find" ' +
      "for a faster local-network delivery once you've scanned the code."
    : "Your browser doesn't support automatic local-network discovery " +
      '(this is expected on Brave — it disables that API for privacy). ' +
      "A backup delivery is trying in the background, or enter your phone's " +
      "IP manually below once you've scanned the code.";

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

  // Checagem síncrona antes de tentar: Firefox nunca teve `system.network`,
  // e o Brave também não (desativa o namespace inteiro por privacidade,
  // mesmo com a permissão concedida — ver lanDiscovery.ts). Nesses casos
  // `sweepLan` já devolveria `null` de qualquer forma, mas pular direto pra
  // mensagem certa evita prometer uma busca que nunca ia rodar de verdade.
  if (!isNetworkDiscoverySupported()) {
    els.statusText.textContent =
      "This browser doesn't support automatic local-network discovery — " +
      "enter your phone's IP manually below.";
    return;
  }

  els.statusText.textContent = 'Looking for your phone on the local network...';

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

// ---------------------------------------------------------------------------
// Propostas de credencial nova (Sessão 134, item 6 do roadmap) — enfileiradas
// por webauthn.content.ts/webauthn-bridge.content.ts quando um site chama
// navigator.credentials.create(). Seção independente do fluxo de QR/entries
// acima (mostrada sempre que há pendências, não faz parte da máquina de
// estados showingQr/received).
// ---------------------------------------------------------------------------

async function refreshPendingEdits(): Promise<void> {
  const pending = await listPendingEdits();
  els.pendingEditsSection.hidden = pending.length === 0;
  els.pendingEditsBadge.textContent = `${pending.length} pending`;
  if (pending.length === 0) {
    els.pendingEditQrWrapper.hidden = true;
    els.pendingEditsStatus.textContent = '';
  }
}

// Achado real (Sessão 135): `refreshPendingEdits()` esconde a seção inteira
// (e limpa `pendingEditsStatus`) assim que `pending.length === 0` — se a
// proposta acabou de ser removida (approve/reject/send bem-sucedido), isso
// acontecia no mesmo instante em que a mensagem terminal ("Saved.", "Sent to
// your phone...") era escrita, apagando-a antes de o usuário ter qualquer
// chance de ler. Dá um tempo antes de deixar `refreshPendingEdits()` rodar
// nesses casos — só quando a proposta continua pendente (falha, sem remoção)
// é que o refresh imediato é seguro (nada pra esconder/limpar).
const TERMINAL_MESSAGE_DISPLAY_MS = 2500;

function scheduleRefreshAfterTerminalMessage(): void {
  setTimeout(() => {
    void refreshPendingEdits();
  }, TERMINAL_MESSAGE_DISPLAY_MS);
}

els.sendToDesktopButton.addEventListener('click', async () => {
  const pending = await listPendingEdits();
  const proposal = pending[0];
  if (!proposal) return;

  els.pendingEditsStatus.textContent = 'Looking for TruthID Desktop on this computer...';
  els.sendToDesktopButton.disabled = true;
  els.sendToPhoneButton.disabled = true;
  let removed = false;
  try {
    const result = await sendToDesktop(proposal);
    if (result.status === 'approved') {
      await removePendingEdit(proposal.id);
      els.pendingEditsStatus.textContent = 'Saved.';
      removed = true;
    } else if (result.status === 'rejected') {
      await removePendingEdit(proposal.id);
      els.pendingEditsStatus.textContent = 'Rejected on the Desktop.';
      removed = true;
    } else if (result.status === 'not-found') {
      els.pendingEditsStatus.textContent =
        "Couldn't find TruthID Desktop running on this computer.";
    } else {
      els.pendingEditsStatus.textContent = `Failed: ${result.status}${result.error ? ` (${result.error})` : ''}`;
    }
    // Achado real (Sessão 135): se essa MESMA proposta também tinha um QR de
    // celular pendente (usuário mandou pro celular, ainda não escaneou,
    // trocou de ideia e aprovou pelo Desktop em vez disso), o botão de retry
    // do celular continuava vivo apontando pra uma proposta já
    // removida/aprovada — clicá-lo reenviaria a mesma proposta pro celular,
    // que poderia aprovar de novo. Limpa a sessão de celular junto.
    if (removed && activeMobileDelivery?.proposal.id === proposal.id) {
      activeMobileDelivery = null;
      els.pendingEditQrWrapper.hidden = true;
    }
  } finally {
    els.sendToDesktopButton.disabled = false;
    els.sendToPhoneButton.disabled = false;
    if (removed) {
      scheduleRefreshAfterTerminalMessage();
    } else {
      await refreshPendingEdits();
    }
  }
});

// Sessão de entrega ativa (QR já mostrado, aguardando o celular escanear e
// abrir o servidor de recebimento) — precisa sobreviver ao retorno do
// handler de clique original pro botão de retry conseguir reusar o MESMO
// sessionId/chave (gerar uma sessão nova geraria um QR diferente do que o
// celular já escaneou). Só uma proposta em voo por vez (mesma premissa dos
// botões desabilitados durante o envio).
let activeMobileDelivery: { session: MobileDeliverySession; proposal: VaultEditProposal } | null =
  null;

async function attemptMobileDelivery(
  session: MobileDeliverySession,
  proposal: VaultEditProposal,
  deliver: () => Promise<boolean> = () => session.send(),
): Promise<void> {
  els.sendToDesktopButton.disabled = true;
  els.sendToPhoneButton.disabled = true;
  els.pendingEditRetryButton.disabled = true;
  els.pendingEditManualConnectButton.disabled = true;
  let delivered = false;
  try {
    const sent = await deliver();
    if (sent) {
      // Best-effort: a extensão não tem como receber confirmação de volta
      // de que o celular publicou de verdade (não roda servidor nenhum) —
      // marca como enviada assim que o PUT chega, mesmo espírito best-effort
      // já aceito em outros lugares do projeto (dead-drop, por exemplo).
      await removePendingEdit(proposal.id);
      els.pendingEditsStatus.textContent = 'Sent to your phone — check it to approve.';
      els.pendingEditQrWrapper.hidden = true;
      activeMobileDelivery = null;
      delivered = true;
    } else {
      // Achado real (Sessão 135): o primeiro envio roda ANTES de o usuário
      // ter tido tempo de escanear o QR de verdade — quase sempre falha na
      // primeira tentativa, não por TTL vencido. `activeMobileDelivery`
      // continua de pé pro botão de retry tentar de novo com a MESMA sessão,
      // depois que o celular já escaneou e está com o servidor no ar.
      els.pendingEditsStatus.textContent =
        "Couldn't reach your phone on the local network — scan the QR, then " +
        'try again.';
    }
  } finally {
    els.sendToDesktopButton.disabled = false;
    els.sendToPhoneButton.disabled = false;
    els.pendingEditRetryButton.disabled = false;
    els.pendingEditManualConnectButton.disabled = false;
    if (delivered) {
      scheduleRefreshAfterTerminalMessage();
    } else {
      await refreshPendingEdits();
    }
  }
}

els.sendToPhoneButton.addEventListener('click', async () => {
  const pending = await listPendingEdits();
  const proposal = pending[0];
  if (!proposal) return;

  // Achado real (Sessão 135): sem desabilitar aqui, um clique duplo rápido
  // corre pelas 3 chamadas assíncronas abaixo (permission/startMobileDelivery/
  // renderQrToCanvas) antes de attemptMobileDelivery desabilitar os botões,
  // gerando 2 sessões de entrega sobrepostas (a 2ª sobrescreve
  // `activeMobileDelivery` da 1ª no meio do envio).
  els.sendToDesktopButton.disabled = true;
  els.sendToPhoneButton.disabled = true;

  const granted = await ensureHostPermission();
  if (!granted) {
    els.pendingEditsStatus.textContent = 'Permission denied.';
    els.sendToDesktopButton.disabled = false;
    els.sendToPhoneButton.disabled = false;
    return;
  }

  // Achado real (Sessão 135, ultrareview): sem guarda aqui, uma falha do
  // QRCode.toCanvas (ex: payload grande demais) deixava o card visível mas
  // em branco, sem status nenhum explicando o que houve, e os botões
  // ficavam presos desabilitados (nada chegava no finally de
  // attemptMobileDelivery, que nunca era alcançado).
  let session: MobileDeliverySession;
  try {
    session = startMobileDelivery(proposal);
    activeMobileDelivery = { session, proposal };
    els.pendingEditQrWrapper.hidden = false;
    await renderQrToCanvas(els.pendingEditQrCanvas, JSON.stringify(session.qrPayload));
    els.pendingEditsStatus.textContent = 'Scan with your phone...';
  } catch (e) {
    activeMobileDelivery = null;
    els.pendingEditQrWrapper.hidden = true;
    els.pendingEditsStatus.textContent = `Failed to generate the QR code: ${e}`;
    els.sendToDesktopButton.disabled = false;
    els.sendToPhoneButton.disabled = false;
    return;
  }

  await attemptMobileDelivery(session, proposal);
});

els.pendingEditRetryButton.addEventListener('click', async () => {
  if (!activeMobileDelivery) return;
  await attemptMobileDelivery(activeMobileDelivery.session, activeMobileDelivery.proposal);
});

// Fallback manual (Sessão 136): a varredura automática de `send()` depende
// de `chrome.system.network`, indisponível no Brave (mesma limitação já
// documentada pro fluxo de leitura do vault, ver `manual-connect` acima) —
// sem isto, "Send to phone"/retry nunca entrega nada no Brave, silenciosamente.
els.pendingEditManualConnectButton.addEventListener('click', async () => {
  if (!activeMobileDelivery) return;
  const ip = els.pendingEditManualIpInput.value.trim();
  if (!ip) return;
  const { session, proposal } = activeMobileDelivery;
  await attemptMobileDelivery(session, proposal, () => session.sendTo(ip));
});

void init();
void refreshPendingEdits();

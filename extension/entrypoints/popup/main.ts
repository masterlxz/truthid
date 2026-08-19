import { secp256k1 } from '@noble/curves/secp256k1';
import { browser } from 'wxt/browser';

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
import { icons } from '../../src/ui/icons';
import { renderVaultList } from '../../src/ui/vaultList';
import { renderEntryDetail } from '../../src/ui/entryDetail';
import { renderEntryForm, type EntryFormSubmitValue } from '../../src/ui/entryForm';
import { renderQrToCanvas } from '../../src/ui/renderQr';
import { base64ToBytes, bytesToHex, hexToBytes } from '../../src/util/bytes';
import {
  addPendingEdit,
  listPendingEdits,
  removePendingEdits,
  type VaultEditProposal,
} from '../../src/vaultEdit/pendingEdits';
import { sendToDesktop } from '../../src/vaultEdit/desktopDelivery';
import { startMobileDelivery, type MobileDeliverySession } from '../../src/vaultEdit/mobileDelivery';
import { loadPinningProviderConfig, savePinningProviderConfig } from '../../src/vaultEdit/pinningProviderConfig';
import { checkForUpdate } from '../../src/updateCheck';

const SESSION_EXPIRY_ALARM = 'truthid-vault-session-expiry';
const START_DEAD_DROP_POLL_MESSAGE = 'truthid-start-dead-drop-poll';
const DEAD_DROP_RESOLVED_MESSAGE = 'truthid-dead-drop-resolved';
// Points at the manual-install section, not the .zip directly — there's no
// real auto-update for a "Load unpacked" extension (see src/updateCheck.ts),
// so the banner needs the reinstall steps, not just a file.
const UPDATE_INSTRUCTIONS_URL = 'https://masterlxz.github.io/truthid/#extension';
const HOST_PERMISSION: chrome.permissions.Permissions = {
  origins: ['http://*/*'],
};

// Chave dos data-i18n* no HTML é lida em runtime (string genérica, não um
// literal conhecido em tempo de compilação) — só aqui, na ponte HTML↔chrome.i18n,
// que o tipo estrito de `getMessage` precisa ser contornado.
type I18nMessageKey = Parameters<typeof browser.i18n.getMessage>[0];
function getMessageByKey(key: string): string {
  return browser.i18n.getMessage(key as I18nMessageKey);
}

// Traduz o markup estático do popup.html via chrome.i18n — só os atributos
// `data-i18n*` marcados no HTML, não o texto montado dinamicamente aqui
// (esse já chama `browser.i18n.getMessage` direto nos handlers abaixo).
function localizePopup(): void {
  document.title = browser.i18n.getMessage('popupTitle');
  for (const el of document.querySelectorAll<HTMLElement>('[data-i18n]')) {
    el.textContent = getMessageByKey(el.dataset.i18n!);
  }
  for (const el of document.querySelectorAll<HTMLInputElement>('[data-i18n-placeholder]')) {
    el.placeholder = getMessageByKey(el.dataset.i18nPlaceholder!);
  }
  for (const el of document.querySelectorAll<HTMLElement>('[data-i18n-aria-label]')) {
    const message = getMessageByKey(el.dataset.i18nAriaLabel!);
    el.setAttribute('aria-label', message);
    el.title = message;
  }
}
localizePopup();

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

// ---------------------------------------------------------------------------
// Navegação entre views — sem framework/router de propósito (popup pequena
// demais pra justificar), só um `hidden` centralizado em vez de espalhado
// pelos handlers como no design anterior. `pairing`/`vault` são as 2 "views
// base" (controladas pela máquina de estados showingQr/received de sempre);
// `entry-detail`/`entry-form`/`pending`/`settings` são overlays que sempre
// voltam pra `baseView` corrente ao fechar (ver `goBack`).
// ---------------------------------------------------------------------------
type ViewName = 'pairing' | 'vault' | 'entry-detail' | 'entry-form' | 'pending' | 'settings';

let baseView: 'pairing' | 'vault' = 'pairing';
// Só relevante quando a view corrente é 'entry-form': volta pra
// 'entry-detail' se veio do botão "Edit" de uma entrada, ou pra `baseView`
// se veio do "+ New" (não existe entrada nenhuma pra voltar a mostrar).
let formReturnsToDetail = false;
let selectedEntry: VaultEntry | null = null;

const els = {
  updateBanner: document.getElementById('update-banner') as HTMLElement,
  updateBannerText: document.getElementById('update-banner-text') as HTMLElement,

  pendingBanner: document.getElementById('pending-banner') as HTMLElement,
  pendingBannerText: document.getElementById('pending-banner-text') as HTMLElement,

  pairingView: document.getElementById('pairing-view') as HTMLElement,
  qrCanvas: document.getElementById('qr-canvas') as HTMLCanvasElement,
  statusText: document.getElementById('status-text') as HTMLElement,
  findButton: document.getElementById('find-button') as HTMLButtonElement,
  manualIpInput: document.getElementById('manual-ip') as HTMLInputElement,
  manualConnectButton: document.getElementById('manual-connect') as HTMLButtonElement,
  newSessionButton: document.getElementById('new-session') as HTMLButtonElement,

  vaultView: document.getElementById('vault-view') as HTMLElement,
  vaultSearchInput: document.getElementById('vault-search') as HTMLInputElement,
  searchIcon: document.querySelector('#vault-view .search-icon') as HTMLElement,
  vaultList: document.getElementById('vault-list') as HTMLElement,
  newEntryButton: document.getElementById('new-entry-button') as HTMLButtonElement,
  settingsButton: document.getElementById('settings-button') as HTMLButtonElement,
  newSessionButton2: document.getElementById('new-session-2') as HTMLButtonElement,

  entryDetailView: document.getElementById('entry-detail-view') as HTMLElement,
  entryFormView: document.getElementById('entry-form-view') as HTMLElement,

  pendingView: document.getElementById('pending-view') as HTMLElement,
  pendingBackButton: document.getElementById('pending-back') as HTMLButtonElement,
  pendingEditsBadge: document.getElementById('pending-edits-badge') as HTMLElement,
  pendingEditsStatus: document.getElementById('pending-edits-status') as HTMLElement,
  sendToDesktopButton: document.getElementById('send-to-desktop') as HTMLButtonElement,
  sendToPhoneButton: document.getElementById('send-to-phone') as HTMLButtonElement,
  pendingEditQrWrapper: document.getElementById('pending-edit-qr-wrapper') as HTMLElement,
  pendingEditQrCanvas: document.getElementById('pending-edit-qr-canvas') as HTMLCanvasElement,
  pendingEditRetryButton: document.getElementById('pending-edit-retry') as HTMLButtonElement,
  pendingEditManualIpInput: document.getElementById('pending-edit-manual-ip') as HTMLInputElement,
  pendingEditManualConnectButton: document.getElementById(
    'pending-edit-manual-connect',
  ) as HTMLButtonElement,

  settingsView: document.getElementById('settings-view') as HTMLElement,
  settingsBackButton: document.getElementById('settings-back') as HTMLButtonElement,
  kuboEndpointInput: document.getElementById('kubo-endpoint') as HTMLInputElement,
  kuboEndpointSaveButton: document.getElementById('kubo-endpoint-save') as HTMLButtonElement,
  kuboEndpointStatus: document.getElementById('kubo-endpoint-status') as HTMLElement,
};

const viewSections: Record<ViewName, HTMLElement> = {
  pairing: els.pairingView,
  vault: els.vaultView,
  'entry-detail': els.entryDetailView,
  'entry-form': els.entryFormView,
  pending: els.pendingView,
  settings: els.settingsView,
};

function showView(name: ViewName): void {
  for (const [key, section] of Object.entries(viewSections)) {
    section.hidden = key !== name;
  }
  if (name === 'pairing' || name === 'vault') baseView = name;
}

function goBack(): void {
  showView(baseView);
}

// Ícones injetados via JS (SVG inline, ver src/ui/icons.ts) em vez de markup
// duplicado no HTML.
els.newEntryButton.innerHTML = icons.plus;
els.settingsButton.innerHTML = icons.gear;
els.pendingBackButton.innerHTML = icons.back;
els.settingsBackButton.innerHTML = icons.back;
els.searchIcon.innerHTML = icons.search;

let currentState: SessionState | null = null;

async function showQr(state: SessionState): Promise<void> {
  showView('pairing');
  els.statusText.textContent = isNetworkDiscoverySupported()
    ? browser.i18n.getMessage('statusFindHintSupported')
    : browser.i18n.getMessage('statusFindHintUnsupported');

  const payload = toQrPayload(
    state.sessionId,
    state.ephemeralPublicKeyHex,
    state.expiresAt,
  );
  await renderQrToCanvas(els.qrCanvas, JSON.stringify(payload));
}

let currentEntries: VaultEntry[] = [];

function renderCurrentVaultList(): void {
  renderVaultList(els.vaultList, currentEntries, {
    query: els.vaultSearchInput.value,
    onSelect: openEntryDetail,
  });
}

function showEntries(entries: VaultEntry[]): void {
  currentEntries = entries;
  showView('vault');
  renderCurrentVaultList();
}

function openEntryDetail(entry: VaultEntry): void {
  selectedEntry = entry;
  renderEntryDetail(els.entryDetailView, entry, {
    onBack: goBack,
    onEdit: openEntryForm,
  });
  showView('entry-detail');
}

function openEntryForm(entry?: VaultEntry): void {
  formReturnsToDetail = !!entry;
  renderEntryForm(els.entryFormView, {
    entry,
    onSubmit: handleEntryFormSubmit,
    onCancel: () => {
      if (formReturnsToDetail && selectedEntry) openEntryDetail(selectedEntry);
      else goBack();
    },
  });
  showView('entry-form');
}

async function handleEntryFormSubmit(value: EntryFormSubmitValue): Promise<void> {
  await addPendingEdit({
    site: value.site,
    url: value.url,
    username: value.username,
    password: value.password,
    notes: value.notes,
    targetEntryId: value.targetEntryId,
  });
  await refreshPendingEdits();
  showView('pending');
}

els.vaultSearchInput.addEventListener('input', renderCurrentVaultList);
els.newEntryButton.addEventListener('click', () => openEntryForm());
els.settingsButton.addEventListener('click', () => showView('settings'));
els.settingsBackButton.addEventListener('click', goBack);
els.pendingBackButton.addEventListener('click', goBack);
els.pendingBanner.addEventListener('click', () => showView('pending'));
els.updateBanner.addEventListener('click', () => browser.tabs.create({ url: UPDATE_INSTRUCTIONS_URL }));

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

async function checkAndShowUpdateBanner(): Promise<void> {
  const newVersion = await checkForUpdate(browser.runtime.getManifest().version);
  if (!newVersion) return;
  els.updateBannerText.textContent = browser.i18n.getMessage('updateBannerText', [newVersion]);
  els.updateBanner.hidden = false;
}

async function init(): Promise<void> {
  void checkAndShowUpdateBanner();

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
    els.statusText.textContent = browser.i18n.getMessage('statusSessionExpired');
    return;
  }

  // Pedido de permissão vem primeiro, aproveitando o gesto de usuário real
  // deste clique — achado real: com o check de LAN antes, browsers sem
  // `chrome.system.network` (Brave/Firefox) nunca chegavam a pedir
  // `http://*/*` nenhuma vez (early-return abaixo sempre disparava primeiro),
  // deixando o ícone in-page de autofill (que depende só dessa permissão,
  // não do sweep de LAN em si) preso pra sempre em "Open the extension icon
  // once..." sem nenhum caminho real de concessão nesses browsers.
  const granted = await ensureHostPermission();
  if (!granted) {
    els.statusText.textContent = browser.i18n.getMessage('statusPermissionDeniedManualIp');
    return;
  }

  // Checagem síncrona antes de tentar: Firefox nunca teve `system.network`,
  // e o Brave também não (desativa o namespace inteiro por privacidade,
  // mesmo com a permissão concedida — ver lanDiscovery.ts). Nesses casos
  // `sweepLan` já devolveria `null` de qualquer forma, mas pular direto pra
  // mensagem certa evita prometer uma busca que nunca ia rodar de verdade.
  if (!isNetworkDiscoverySupported()) {
    els.statusText.textContent = browser.i18n.getMessage('statusDiscoveryUnsupported');
    return;
  }

  els.statusText.textContent = browser.i18n.getMessage('statusLookingForPhone');

  const blob = await sweepLan(currentState.sessionId);
  if (blob) {
    await handleBlob(blob);
    return;
  }

  if (currentState.status === 'received') return; // dead-drop já resolveu em background enquanto o sweep rodava

  els.statusText.textContent = browser.i18n.getMessage('statusCouldNotFindPhone');
});

els.manualConnectButton.addEventListener('click', async () => {
  if (!currentState) return;
  if (isExpired(currentState)) {
    els.statusText.textContent = browser.i18n.getMessage('statusSessionExpired');
    return;
  }

  const ip = els.manualIpInput.value.trim();
  if (!ip) return;

  els.statusText.textContent = browser.i18n.getMessage('statusTryingIp', [ip]);
  for (const port of CANDIDATE_PORTS) {
    const blob = await fetchSessionBlob(ip, port, currentState.sessionId);
    if (blob) {
      await handleBlob(blob);
      return;
    }
  }
  els.statusText.textContent = browser.i18n.getMessage('statusCouldNotReachPhone');
});

async function startNewSession(): Promise<void> {
  await clearSession();
  currentState = await createNewSession();
  await showQr(currentState);
}

els.newSessionButton.addEventListener('click', () => void startNewSession());
els.newSessionButton2.addEventListener('click', () => void startNewSession());

// ---------------------------------------------------------------------------
// Propostas de credencial nova/edição (Sessão 134, item 6 do roadmap;
// Sessão 205, formulário manual + edição de entrada existente) — enfileiradas
// por webauthn.content.ts/webauthn-bridge.content.ts quando um site chama
// navigator.credentials.create(), por newCredentialCapture.ts (formulário de
// cadastro detectado numa página real), ou agora também por
// handleEntryFormSubmit acima (formulário "+ New"/"Edit" da própria popup).
// View própria (`pending`), aberta pela faixa fina no topo ou logo após
// enfileirar uma proposta pelo formulário — não é mais uma seção sempre
// visível junto da lista.
// ---------------------------------------------------------------------------

async function refreshPendingEdits(): Promise<void> {
  const pending = await listPendingEdits();
  els.pendingEditsBadge.textContent = browser.i18n.getMessage('pendingCountBadge', [
    String(pending.length),
  ]);
  els.pendingBanner.hidden = pending.length === 0;
  els.pendingBannerText.textContent =
    pending.length === 1
      ? browser.i18n.getMessage('pendingBannerTextSingular')
      : browser.i18n.getMessage('pendingBannerTextPlural', [String(pending.length)]);
  if (pending.length === 0) {
    els.pendingEditQrWrapper.hidden = true;
    els.pendingEditsStatus.textContent = '';
    // Achado real (Sessão 135, preservado no redesenho da Sessão 205): se a
    // view de pending estava aberta mostrando a mensagem terminal ("Saved.",
    // "Sent to your phone..."), só volta pra baseView depois do delay em
    // `scheduleRefreshAfterTerminalMessage` — nunca no meio da leitura.
    if (!els.pendingView.hidden) goBack();
  }
}

// Achado real (Sessão 135): `refreshPendingEdits()` escondia a seção inteira
// (e limpava `pendingEditsStatus`) assim que `pending.length === 0` — se a
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
  if (pending.length === 0) return;

  els.pendingEditsStatus.textContent = browser.i18n.getMessage('pendingStatusLookingForDesktop');
  els.sendToDesktopButton.disabled = true;
  els.sendToPhoneButton.disabled = true;
  let removed = false;
  try {
    const result = await sendToDesktop(pending);
    if (result.status === 'approved') {
      await removePendingEdits(pending.map((p) => p.id));
      els.pendingEditsStatus.textContent = browser.i18n.getMessage('savedStatus');
      removed = true;
    } else if (result.status === 'rejected') {
      await removePendingEdits(pending.map((p) => p.id));
      els.pendingEditsStatus.textContent = browser.i18n.getMessage('pendingStatusRejectedOnDesktop');
      removed = true;
    } else if (result.status === 'not-found') {
      els.pendingEditsStatus.textContent = browser.i18n.getMessage('pendingStatusNotFoundDesktop');
    } else {
      els.pendingEditsStatus.textContent = result.error
        ? browser.i18n.getMessage('pendingStatusFailedWithError', [result.status, result.error])
        : browser.i18n.getMessage('pendingStatusFailed', [result.status]);
    }
    // Achado real (Sessão 135, agora por leva inteira depois do P29): se
    // essa MESMA leva também tinha um QR de celular pendente (usuário
    // mandou pro celular, ainda não escaneou, trocou de ideia e aprovou
    // pelo Desktop em vez disso), o botão de retry do celular continuava
    // vivo apontando pra propostas já removidas/aprovadas — clicá-lo
    // reenviaria a mesma leva pro celular, que poderia aprovar de novo.
    // Limpa a sessão de celular junto (mesma leva = mesmo conjunto de ids).
    const sentIds = new Set(pending.map((p) => p.id));
    const activeIds = activeMobileDelivery?.proposals.map((p) => p.id) ?? [];
    if (removed && activeIds.length > 0 && activeIds.every((id) => sentIds.has(id))) {
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
// celular já escaneou). Só uma leva em voo por vez (mesma premissa dos
// botões desabilitados durante o envio) — a leva inteira (1+ propostas,
// sync em lote do P29) viaja numa sessão só.
let activeMobileDelivery: {
  session: MobileDeliverySession;
  proposals: VaultEditProposal[];
} | null = null;

async function attemptMobileDelivery(
  session: MobileDeliverySession,
  proposals: VaultEditProposal[],
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
      await removePendingEdits(proposals.map((p) => p.id));
      els.pendingEditsStatus.textContent = browser.i18n.getMessage('pendingStatusSentToPhone');
      els.pendingEditQrWrapper.hidden = true;
      activeMobileDelivery = null;
      delivered = true;
    } else {
      // Achado real (Sessão 135): o primeiro envio roda ANTES de o usuário
      // ter tido tempo de escanear o QR de verdade — quase sempre falha na
      // primeira tentativa, não por TTL vencido. `activeMobileDelivery`
      // continua de pé pro botão de retry tentar de novo com a MESMA sessão,
      // depois que o celular já escaneou e está com o servidor no ar.
      els.pendingEditsStatus.textContent = browser.i18n.getMessage(
        'pendingStatusCouldNotReachPhoneRetry',
      );
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
  if (pending.length === 0) return;

  // Achado real (Sessão 135): sem desabilitar aqui, um clique duplo rápido
  // corre pelas 3 chamadas assíncronas abaixo (permission/startMobileDelivery/
  // renderQrToCanvas) antes de attemptMobileDelivery desabilitar os botões,
  // gerando 2 sessões de entrega sobrepostas (a 2ª sobrescreve
  // `activeMobileDelivery` da 1ª no meio do envio).
  els.sendToDesktopButton.disabled = true;
  els.sendToPhoneButton.disabled = true;

  const granted = await ensureHostPermission();
  if (!granted) {
    els.pendingEditsStatus.textContent = browser.i18n.getMessage('permissionDenied');
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
    session = startMobileDelivery(pending);
    activeMobileDelivery = { session, proposals: pending };
    els.pendingEditQrWrapper.hidden = false;
    await renderQrToCanvas(els.pendingEditQrCanvas, JSON.stringify(session.qrPayload));
    els.pendingEditsStatus.textContent = browser.i18n.getMessage('pendingStatusScanWithPhone');
  } catch (e) {
    activeMobileDelivery = null;
    els.pendingEditQrWrapper.hidden = true;
    els.pendingEditsStatus.textContent = browser.i18n.getMessage('failedToGenerateQr', [String(e)]);
    els.sendToDesktopButton.disabled = false;
    els.sendToPhoneButton.disabled = false;
    return;
  }

  await attemptMobileDelivery(session, pending);
});

els.pendingEditRetryButton.addEventListener('click', async () => {
  if (!activeMobileDelivery) return;
  await attemptMobileDelivery(activeMobileDelivery.session, activeMobileDelivery.proposals);
});

// Fallback manual (Sessão 136): a varredura automática de `send()` depende
// de `chrome.system.network`, indisponível no Brave (mesma limitação já
// documentada pro fluxo de leitura do vault, ver `manual-connect` acima) —
// sem isto, "Send to phone"/retry nunca entrega nada no Brave, silenciosamente.
els.pendingEditManualConnectButton.addEventListener('click', async () => {
  if (!activeMobileDelivery) return;
  const ip = els.pendingEditManualIpInput.value.trim();
  if (!ip) return;
  const { session, proposals } = activeMobileDelivery;
  await attemptMobileDelivery(session, proposals, () => session.sendTo(ip));
});

// Config do endpoint Kubo usado só pra publicar o dead-drop cross-network
// do vault-edit (item 6 do backlog, `deadDropPublish.ts`) — opcional, sem
// endpoint configurado o "Send to phone" continua funcionando normal via
// LAN/IP manual, só sem o fallback cross-network.
async function loadKuboEndpointIntoForm(): Promise<void> {
  const config = await loadPinningProviderConfig();
  els.kuboEndpointInput.value = config?.kuboEndpointUrl ?? '';
}

els.kuboEndpointSaveButton.addEventListener('click', async () => {
  await savePinningProviderConfig(els.kuboEndpointInput.value);
  els.kuboEndpointStatus.textContent = browser.i18n.getMessage('savedStatus');
});

void loadKuboEndpointIntoForm();

void init();
void refreshPendingEdits();

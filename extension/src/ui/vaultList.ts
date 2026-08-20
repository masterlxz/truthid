import { t } from '../i18n';

import type { VaultEntry } from '../session/sessionState';
import { iconButton } from './icons';

/**
 * Lista compacta do vault — 1 linha por entrada (avatar + site + username +
 * copiar), com busca em memória. Substitui o antigo `renderEntries.ts` (card
 * alto, 1 campo por linha, sem busca/detalhe) — estrutura inspirada na
 * extensão do Bitwarden, paleta/tipografia continuam as do TruthID
 * (`theme.css`).
 */

/** Filtra por site/username, substring case-insensitive. Exportado à parte
 * pra ser testável sem precisar montar DOM. */
export function filterEntries(entries: VaultEntry[], query: string): VaultEntry[] {
  const q = query.trim().toLowerCase();
  if (!q) return entries;
  return entries.filter((entry) => {
    const site = (entry.site || entry.url || '').toLowerCase();
    return site.includes(q) || entry.username.toLowerCase().includes(q);
  });
}

// Hash simples e determinístico (FNV-1a-like) só pra variar a cor do avatar
// entre sites diferentes — não é criptográfico, não precisa ser.
function hueFor(text: string): number {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
  }
  return hash % 360;
}

function avatar(label: string): HTMLElement {
  const el = document.createElement('div');
  el.className = 'vault-avatar';
  el.style.backgroundColor = `hsl(${hueFor(label)}, 45%, 32%)`;
  el.textContent = (label.trim()[0] || '?').toUpperCase();
  return el;
}

export function renderVaultList(
  container: HTMLElement,
  entries: VaultEntry[],
  options: { query: string; onSelect: (entry: VaultEntry) => void },
): void {
  container.innerHTML = '';
  const filtered = filterEntries(entries, options.query);

  if (entries.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = t('noEntriesInProfile');
    container.appendChild(empty);
    return;
  }

  if (filtered.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = t('noEntriesMatchSearch');
    container.appendChild(empty);
    return;
  }

  for (const entry of filtered) {
    container.appendChild(renderRow(entry, options.onSelect));
  }
}

function renderRow(entry: VaultEntry, onSelect: (entry: VaultEntry) => void): HTMLElement {
  const label = entry.site || entry.url || entry.username || '?';

  const row = document.createElement('div');
  row.className = 'vault-row';
  row.tabIndex = 0;
  row.setAttribute('role', 'button');
  row.appendChild(avatar(label));

  const text = document.createElement('div');
  text.className = 'vault-row-text';

  const site = document.createElement('div');
  site.className = 'vault-row-site';
  site.textContent = label;
  text.appendChild(site);

  if (entry.username) {
    const username = document.createElement('div');
    username.className = 'vault-row-username';
    username.textContent = entry.username;
    text.appendChild(username);
  }
  row.appendChild(text);

  const copy = iconButton('copy', { label: t('copyPasswordAriaLabel') });
  const copyIconHtml = copy.innerHTML;
  copy.addEventListener('click', async (event) => {
    event.stopPropagation();
    await navigator.clipboard.writeText(entry.password);
    copy.textContent = '✓';
    setTimeout(() => {
      copy.innerHTML = copyIconHtml;
    }, 900);
  });
  row.appendChild(copy);

  function select() {
    onSelect(entry);
  }
  row.addEventListener('click', select);
  row.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      select();
    }
  });

  return row;
}

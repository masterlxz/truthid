import type { VaultEntry } from '../session/sessionState';
import { setNativeValue } from './fillField';
import { GET_MATCHING_ENTRIES_MESSAGE } from './messages';

// Só o subconjunto de tokens de ../ui/theme.css que o overlay usa — não dá
// pra importar o CSS de tokens direto porque o Shadow DOM isola o overlay
// do CSS da página hospedeira (e do resto da extensão): precisa da própria
// cópia, embutida.
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
  .dropdown {
    position: fixed;
    min-width: 220px;
    max-width: 280px;
    background: #111820;
    border: 1px solid #1f2630;
    border-radius: 8px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
    font-family: 'Inter', system-ui, sans-serif;
    font-size: 13px;
    color: #e6edf3;
    z-index: 2147483647;
    overflow: hidden;
  }
  .dropdown-item {
    padding: 8px 12px;
    cursor: pointer;
  }
  .dropdown-item:hover {
    background: #1f2630;
  }
  .dropdown-item .site {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .dropdown-item .username {
    color: #9fb1c2;
    font-size: 0.9em;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
`;

/**
 * Pergunta ao background quais entradas do vault batem com o hostname
 * atual, e só se houver ao menos uma, cria o ícone ancorado ao campo de
 * senha (nunca mostra um ícone que só diria "nenhuma entrada" — silêncio é
 * melhor que ruído numa página que não tem nada a ver com o vault).
 */
export async function attachAutofillIconIfMatches(
  passwordField: HTMLInputElement,
  usernameField: HTMLInputElement | null,
): Promise<void> {
  let entries: VaultEntry[];
  try {
    const response = await chrome.runtime.sendMessage({
      type: GET_MATCHING_ENTRIES_MESSAGE,
      hostname: location.hostname,
    });
    entries = (response?.entries as VaultEntry[] | undefined) ?? [];
  } catch {
    // Sem service worker vivo pra responder, ou nenhuma sessão — não mostra nada.
    return;
  }
  if (entries.length === 0) return;

  attachAutofillIcon(passwordField, usernameField, entries);
}

function attachAutofillIcon(
  passwordField: HTMLInputElement,
  usernameField: HTMLInputElement | null,
  entries: VaultEntry[],
): void {
  const host = document.createElement('div');
  document.documentElement.appendChild(host);
  const shadow = host.attachShadow({ mode: 'closed' });

  const style = document.createElement('style');
  style.textContent = OVERLAY_STYLE;
  shadow.appendChild(style);

  const icon = document.createElement('button');
  icon.className = 'icon';
  icon.type = 'button';
  icon.setAttribute('aria-label', 'Fill with TruthID');
  const iconImg = document.createElement('img');
  iconImg.src = chrome.runtime.getURL('icon/32.png');
  iconImg.alt = '';
  icon.appendChild(iconImg);
  shadow.appendChild(icon);

  function positionIcon(): void {
    const rect = passwordField.getBoundingClientRect();
    icon.style.top = `${rect.top + (rect.height - 22) / 2}px`;
    icon.style.left = `${rect.right - 26}px`;
  }
  positionIcon();
  window.addEventListener('scroll', positionIcon, true);
  window.addEventListener('resize', positionIcon);

  let dropdown: HTMLElement | null = null;

  function closeDropdown(): void {
    dropdown?.remove();
    dropdown = null;
  }

  function openDropdown(): void {
    dropdown = document.createElement('div');
    dropdown.className = 'dropdown';
    const rect = icon.getBoundingClientRect();
    dropdown.style.top = `${rect.bottom + 4}px`;
    dropdown.style.left = `${Math.max(0, rect.right - 220)}px`;

    for (const entry of entries) {
      const item = document.createElement('div');
      item.className = 'dropdown-item';

      const site = document.createElement('div');
      site.className = 'site';
      site.textContent = entry.site || entry.url || '(untitled)';
      item.appendChild(site);

      const username = document.createElement('div');
      username.className = 'username';
      username.textContent = entry.username;
      item.appendChild(username);

      item.addEventListener('click', () => {
        if (usernameField) setNativeValue(usernameField, entry.username);
        setNativeValue(passwordField, entry.password);
        closeDropdown();
      });
      dropdown.appendChild(item);
    }
    shadow.appendChild(dropdown);
  }

  icon.addEventListener('click', (event) => {
    event.stopPropagation();
    if (dropdown) {
      closeDropdown();
    } else {
      openDropdown();
    }
  });

  document.addEventListener('click', closeDropdown);
}

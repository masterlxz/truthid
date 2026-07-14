import type { VaultEntry } from '../session/sessionState';

/**
 * Lista somente-leitura das entradas recebidas — sem autofill, sem injeção
 * de content script em páginas arbitrárias (fora do escopo desta fatia).
 * Só site/usuário/senha (mascarada, com toggle de revelar) + copiar.
 */
export function renderEntries(container: HTMLElement, entries: VaultEntry[]): void {
  container.innerHTML = '';

  if (entries.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = 'No entries in this profile.';
    container.appendChild(empty);
    return;
  }

  for (const entry of entries) {
    container.appendChild(renderEntryRow(entry));
  }
}

function renderEntryRow(entry: VaultEntry): HTMLElement {
  const row = document.createElement('div');
  row.className = 'entry-row';

  const site = document.createElement('div');
  site.className = 'entry-site';
  site.textContent = entry.site || entry.url || '(untitled)';
  row.appendChild(site);

  row.appendChild(fieldWithCopy('Username', entry.username));
  row.appendChild(passwordField(entry.password));

  return row;
}

function fieldWithCopy(label: string, value: string): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'entry-field';

  const text = document.createElement('span');
  text.textContent = `${label}: ${value}`;
  wrap.appendChild(text);

  wrap.appendChild(copyButton(() => value));
  return wrap;
}

function passwordField(password: string): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'entry-field';

  let revealed = false;
  const text = document.createElement('span');
  text.textContent = `Password: ${'•'.repeat(8)}`;
  wrap.appendChild(text);

  const toggle = document.createElement('button');
  toggle.textContent = 'Show';
  toggle.addEventListener('click', () => {
    revealed = !revealed;
    text.textContent = `Password: ${revealed ? password : '•'.repeat(8)}`;
    toggle.textContent = revealed ? 'Hide' : 'Show';
  });
  wrap.appendChild(toggle);

  wrap.appendChild(copyButton(() => password));
  return wrap;
}

function copyButton(getValue: () => string): HTMLElement {
  const button = document.createElement('button');
  button.textContent = 'Copy';
  button.addEventListener('click', async () => {
    await navigator.clipboard.writeText(getValue());
    const original = button.textContent;
    button.textContent = 'Copied!';
    setTimeout(() => {
      button.textContent = original;
    }, 1000);
  });
  return button;
}

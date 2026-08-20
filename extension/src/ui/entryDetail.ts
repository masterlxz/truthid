import { t } from '../i18n';

import type { VaultEntry } from '../session/sessionState';
import { icons, iconButton } from './icons';

/** View de detalhe de uma entrada — username/senha com copiar/revelar,
 * botão "Edit" no rodapé (abre entryForm.ts pré-preenchido). */
export function renderEntryDetail(
  container: HTMLElement,
  entry: VaultEntry,
  options: { onBack: () => void; onEdit: (entry: VaultEntry) => void },
): void {
  container.innerHTML = '';

  const header = document.createElement('div');
  header.className = 'detail-header';
  const back = iconButton('back', { label: t('backToVaultAriaLabel') });
  back.addEventListener('click', options.onBack);
  header.appendChild(back);
  const title = document.createElement('h2');
  title.className = 'detail-title';
  title.textContent = entry.site || entry.url || t('untitledEntry');
  header.appendChild(title);
  container.appendChild(header);

  const card = document.createElement('div');
  card.className = 'card';

  if (entry.username) {
    card.appendChild(fieldRow(t('fieldUsername'), entry.username, () => entry.username));
  }
  card.appendChild(passwordRow(entry.password));
  if (entry.url) {
    card.appendChild(fieldRow(t('fieldUrl'), entry.url, () => entry.url));
  }
  if (entry.notes) {
    const notesWrap = document.createElement('div');
    notesWrap.className = 'field';
    const label = document.createElement('label');
    label.textContent = t('fieldNotes');
    notesWrap.appendChild(label);
    const notes = document.createElement('p');
    notes.className = 'muted';
    notes.style.margin = '0';
    notes.style.whiteSpace = 'pre-wrap';
    notes.textContent = entry.notes;
    notesWrap.appendChild(notes);
    card.appendChild(notesWrap);
  }
  if (entry.passkey) {
    const badge = document.createElement('p');
    badge.className = 'muted';
    badge.textContent = t('passkeyBadge', [entry.passkey.rp_id]);
    card.appendChild(badge);
  }

  container.appendChild(card);

  const editButton = document.createElement('button');
  editButton.textContent = t('editButton');
  editButton.style.marginTop = '0.75rem';
  editButton.addEventListener('click', () => options.onEdit(entry));
  container.appendChild(editButton);
}

function fieldRow(label: string, value: string, getValue: () => string): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'field';

  const labelEl = document.createElement('label');
  labelEl.textContent = label;
  wrap.appendChild(labelEl);

  const row = document.createElement('div');
  row.className = 'detail-field-row';
  const text = document.createElement('span');
  text.className = 'detail-field-value';
  text.textContent = value;
  row.appendChild(text);
  row.appendChild(copyIconButton(getValue));
  wrap.appendChild(row);

  return wrap;
}

function passwordRow(password: string): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'field';

  const label = document.createElement('label');
  label.textContent = t('fieldPassword');
  wrap.appendChild(label);

  const row = document.createElement('div');
  row.className = 'detail-field-row';

  let revealed = false;
  const text = document.createElement('span');
  text.className = 'detail-field-value monospace';
  text.textContent = '•'.repeat(10);
  row.appendChild(text);

  const toggle = iconButton('eye', { label: t('showPasswordAriaLabel') });
  toggle.addEventListener('click', () => {
    revealed = !revealed;
    text.textContent = revealed ? password : '•'.repeat(10);
    toggle.innerHTML = revealed ? icons.eyeOff : icons.eye;
    const label = t(revealed ? 'hidePasswordAriaLabel' : 'showPasswordAriaLabel');
    toggle.setAttribute('aria-label', label);
    toggle.title = label;
  });
  row.appendChild(toggle);
  row.appendChild(copyIconButton(() => password));
  wrap.appendChild(row);

  return wrap;
}

function copyIconButton(getValue: () => string): HTMLElement {
  const button = iconButton('copy', { label: t('copyAriaLabel') });
  const original = button.innerHTML;
  button.addEventListener('click', async () => {
    await navigator.clipboard.writeText(getValue());
    button.textContent = '✓';
    setTimeout(() => {
      button.innerHTML = original;
    }, 900);
  });
  return button;
}

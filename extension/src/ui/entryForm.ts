import type { VaultEntry } from '../session/sessionState';
import { generatePassword } from '../util/passwordGenerator';

export interface EntryFormSubmitValue {
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  targetEntryId?: string;
}

/** Formulário de criar/editar senha — serve os dois casos: `entry` presente
 * (edição, campos pré-preenchidos, submit inclui `targetEntryId`) ou ausente
 * (criação, `targetEntryId` fica de fora). Não fala com `pendingEdits.ts`
 * diretamente — só devolve o valor via `onSubmit`, quem enfileira é
 * `main.ts` (mantém este módulo sem I/O, mais fácil de testar). */
export function renderEntryForm(
  container: HTMLElement,
  options: {
    entry?: VaultEntry;
    onSubmit: (value: EntryFormSubmitValue) => void;
    onCancel: () => void;
  },
): void {
  container.innerHTML = '';
  const isEditing = !!options.entry;

  const header = document.createElement('div');
  header.className = 'detail-header';
  const title = document.createElement('h2');
  title.className = 'detail-title';
  title.textContent = isEditing ? 'Edit password' : 'New password';
  header.appendChild(title);
  container.appendChild(header);

  const form = document.createElement('form');
  form.className = 'card entry-form';

  const site = textField('site-input', 'Site', options.entry?.site ?? '');
  const url = textField('url-input', 'URL', options.entry?.url ?? '', 'https://example.com');
  const username = textField('username-input', 'Username', options.entry?.username ?? '');
  const { field: passwordField, input: passwordInput } = passwordFieldWithGenerate(
    options.entry?.password ?? '',
  );
  const notes = textAreaField('notes-input', 'Notes', options.entry?.notes ?? '');

  form.appendChild(site.field);
  form.appendChild(url.field);
  form.appendChild(username.field);
  form.appendChild(passwordField);
  form.appendChild(notes.field);

  const actions = document.createElement('div');
  actions.className = 'actions-row';
  const submit = document.createElement('button');
  submit.type = 'submit';
  submit.textContent = isEditing ? 'Save changes' : 'Add password';
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.className = 'secondary-action-button';
  cancel.textContent = 'Cancel';
  cancel.addEventListener('click', options.onCancel);
  actions.appendChild(submit);
  actions.appendChild(cancel);
  form.appendChild(actions);

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    options.onSubmit({
      site: site.input.value.trim(),
      url: url.input.value.trim(),
      username: username.input.value.trim(),
      password: passwordInput.value,
      notes: notes.input.value,
      targetEntryId: options.entry?.id,
    });
  });

  container.appendChild(form);
}

function textField(
  id: string,
  label: string,
  value: string,
  placeholder = '',
): { field: HTMLElement; input: HTMLInputElement } {
  const field = document.createElement('div');
  field.className = 'field';
  const labelEl = document.createElement('label');
  labelEl.htmlFor = id;
  labelEl.textContent = label;
  field.appendChild(labelEl);
  const input = document.createElement('input');
  input.id = id;
  input.type = 'text';
  input.value = value;
  input.placeholder = placeholder;
  field.appendChild(input);
  return { field, input };
}

function textAreaField(
  id: string,
  label: string,
  value: string,
): { field: HTMLElement; input: HTMLTextAreaElement } {
  const field = document.createElement('div');
  field.className = 'field';
  const labelEl = document.createElement('label');
  labelEl.htmlFor = id;
  labelEl.textContent = label;
  field.appendChild(labelEl);
  const input = document.createElement('textarea');
  input.id = id;
  input.rows = 2;
  input.value = value;
  field.appendChild(input);
  return { field, input };
}

// Opções default do gerador — sem UI de configuração avançada nesta rodada
// (ver plano: comprimento/exclusão de símbolos ambíguos ficam pra depois).
const GENERATOR_DEFAULTS = {
  length: 16,
  uppercase: true,
  lowercase: true,
  numbers: true,
  symbols: true,
} as const;

function passwordFieldWithGenerate(value: string): {
  field: HTMLElement;
  input: HTMLInputElement;
} {
  const field = document.createElement('div');
  field.className = 'field';
  const label = document.createElement('label');
  label.htmlFor = 'password-input';
  label.textContent = 'Password';
  field.appendChild(label);

  const row = document.createElement('div');
  row.className = 'manual-row';
  const input = document.createElement('input');
  input.id = 'password-input';
  input.type = 'text';
  input.value = value;
  row.appendChild(input);

  const generate = document.createElement('button');
  generate.type = 'button';
  generate.textContent = 'Generate';
  generate.addEventListener('click', () => {
    input.value = generatePassword(GENERATOR_DEFAULTS);
  });
  row.appendChild(generate);

  field.appendChild(row);
  return { field, input };
}

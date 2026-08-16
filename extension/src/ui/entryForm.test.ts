// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest';
import { renderEntryForm } from './entryForm';
import type { VaultEntry } from '../session/sessionState';
import enMessages from '../../public/_locales/en/messages.json';

type MessageEntry = { message: string; placeholders?: Record<string, { content: string }> };

// Fake mínimo de `browser.i18n.getMessage`, lendo do dicionário `en` real —
// mantém as asserções abaixo testando o texto de verdade que o usuário vê,
// não uma chave arbitrária, sem precisar de todo o setup do WxtVitest.
// `browser` (`wxt/browser`) é um `const` avaliado uma vez no import do
// módulo a partir de `globalThis.chrome` — stubar `globalThis.chrome` num
// `beforeEach` chegaria tarde demais (o binding já teria capturado
// `undefined`), então mocka-se o módulo inteiro em vez disso.
function fakeGetMessage(key: string, substitutions?: string | string[]): string {
  const entry = (enMessages as Record<string, MessageEntry>)[key];
  if (!entry) return key;
  let text = entry.message;
  const subs = Array.isArray(substitutions) ? substitutions : substitutions ? [substitutions] : [];
  for (const [name, { content }] of Object.entries(entry.placeholders ?? {})) {
    const match = /^\$(\d+)$/.exec(content);
    if (match) text = text.replaceAll(`$${name.toUpperCase()}$`, subs[Number(match[1]) - 1] ?? '');
  }
  return text;
}

vi.mock('wxt/browser', () => ({
  browser: { i18n: { getMessage: fakeGetMessage } },
}));

// Elemento solto, nunca anexado ao document.body: `querySelector('#id')`
// funciona igual num nó desconectado, e evita colisão de ids duplicados
// entre testes (jsdom/nwsapi atalha seletores só-de-id via um lookup global
// tipo `getElementById`, que sempre acha o 1º elemento com aquele id no
// documento inteiro — se o container de um teste anterior continuasse
// pendurado no body com o mesmo id, o `querySelector` deste teste acharia o
// elemento ERRADO, de outro teste).
function container(): HTMLElement {
  return document.createElement('div');
}

function fillAndSubmit(root: HTMLElement, values: Record<string, string>): void {
  for (const [id, value] of Object.entries(values)) {
    const input = root.querySelector<HTMLInputElement | HTMLTextAreaElement>(`#${id}`);
    if (!input) throw new Error(`missing field #${id}`);
    input.value = value;
  }
  const form = root.querySelector('form');
  if (!form) throw new Error('missing form');
  form.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
}

describe('renderEntryForm', () => {
  it('new entry: submits without targetEntryId', () => {
    const root = container();
    const onSubmit = vi.fn();
    renderEntryForm(root, { onSubmit, onCancel: vi.fn() });

    fillAndSubmit(root, {
      'site-input': 'example.com',
      'username-input': 'alice',
      'password-input': 'hunter2',
    });

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        site: 'example.com',
        username: 'alice',
        password: 'hunter2',
        targetEntryId: undefined,
      }),
    );
  });

  it('editing an entry: pre-fills fields and submits with targetEntryId', () => {
    const root = container();
    const onSubmit = vi.fn();
    const entry: VaultEntry = {
      id: 'existing-id',
      site: 'example.com',
      url: '',
      username: 'alice',
      password: 'old-password',
      notes: 'old notes',
      profiles: [],
    };
    renderEntryForm(root, { entry, onSubmit, onCancel: vi.fn() });

    expect(root.querySelector<HTMLInputElement>('#site-input')?.value).toBe('example.com');
    expect(root.querySelector<HTMLInputElement>('#username-input')?.value).toBe('alice');
    expect(root.querySelector<HTMLInputElement>('#password-input')?.value).toBe('old-password');

    fillAndSubmit(root, { 'password-input': 'new-password' });

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        site: 'example.com',
        username: 'alice',
        password: 'new-password',
        targetEntryId: 'existing-id',
      }),
    );
  });

  it('Generate button fills the password field', () => {
    const root = container();
    renderEntryForm(root, { onSubmit: vi.fn(), onCancel: vi.fn() });

    const generateButton = Array.from(root.querySelectorAll('button')).find(
      (b) => b.textContent === 'Generate',
    );
    if (!generateButton) throw new Error('missing Generate button');
    generateButton.click();

    const passwordInput = root.querySelector<HTMLInputElement>('#password-input');
    expect(passwordInput?.value.length).toBe(16);
  });

  it('Cancel calls onCancel without submitting', () => {
    const root = container();
    const onSubmit = vi.fn();
    const onCancel = vi.fn();
    renderEntryForm(root, { onSubmit, onCancel });

    const cancelButton = Array.from(root.querySelectorAll('button')).find(
      (b) => b.textContent === 'Cancel',
    );
    cancelButton?.click();

    expect(onCancel).toHaveBeenCalledOnce();
    expect(onSubmit).not.toHaveBeenCalled();
  });
});

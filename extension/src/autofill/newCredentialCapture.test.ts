// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { attachNewCredentialCapture } from './newCredentialCapture';
import { GET_MATCHING_ENTRIES_MESSAGE, VAULT_EDIT_ENQUEUE_MESSAGE } from './messages';

interface FakeEntry {
  username: string;
}

interface FakeProposalMessage {
  type?: string;
  proposal?: { site: string; url: string; username: string; password: string; notes: string };
}

function buildFakeChrome(existingEntries: FakeEntry[]) {
  const sendMessage = vi.fn(async (message: FakeProposalMessage) => {
    if (message.type === GET_MATCHING_ENTRIES_MESSAGE) {
      return { entries: existingEntries };
    }
    return undefined;
  });
  return { runtime: { sendMessage } };
}

function buildSignupForm(): {
  form: HTMLFormElement;
  usernameField: HTMLInputElement;
  passwordField: HTMLInputElement;
} {
  const form = document.createElement('form');
  const usernameField = document.createElement('input');
  usernameField.type = 'text';
  usernameField.autocomplete = 'username';
  const passwordField = document.createElement('input');
  passwordField.type = 'password';
  form.appendChild(usernameField);
  form.appendChild(passwordField);
  document.body.appendChild(form);
  return { form, usernameField, passwordField };
}

function submit(form: HTMLFormElement): void {
  form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
}

// Espera as duas awaits internas (hasExistingMatch → proposeIfNew) resolverem
// antes de checar as chamadas — attachNewCredentialCapture nunca aguarda o
// handler de submit.
async function flushAsync(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe('attachNewCredentialCapture', () => {
  beforeEach(() => {
    vi.stubGlobal('location', { hostname: 'example.com', origin: 'https://example.com' });
  });

  afterEach(() => {
    document.body.innerHTML = '';
    vi.unstubAllGlobals();
    // @ts-expect-error -- só existe em teste
    delete globalThis.chrome;
  });

  // Usernames distintos por teste — `proposedThisPageLoad` é estado de
  // módulo (dedupe por hostname+username, de propósito, ver comentário em
  // newCredentialCapture.ts), então persiste entre os testes deste arquivo
  // como um reload de página nunca acontece de verdade aqui. Usar o mesmo
  // username em 2 testes diferentes faria o 2º "herdar" o dedupe do 1º.

  it('propõe credencial nova quando não há entrada existente com esse username', async () => {
    const fakeChrome = buildFakeChrome([]);
    globalThis.chrome = fakeChrome as unknown as typeof chrome;
    const { form, usernameField, passwordField } = buildSignupForm();
    usernameField.value = 'user-propose';
    passwordField.value = 'hunter2';

    attachNewCredentialCapture(passwordField, usernameField);
    submit(form);
    await flushAsync();

    expect(fakeChrome.runtime.sendMessage).toHaveBeenCalledWith({
      type: VAULT_EDIT_ENQUEUE_MESSAGE,
      proposal: {
        site: 'example.com',
        url: 'https://example.com',
        username: 'user-propose',
        password: 'hunter2',
        notes: '',
      },
    });
  });

  it('não propõe quando já existe entrada com esse username exato', async () => {
    const fakeChrome = buildFakeChrome([{ username: 'user-existing' }]);
    globalThis.chrome = fakeChrome as unknown as typeof chrome;
    const { form, usernameField, passwordField } = buildSignupForm();
    usernameField.value = 'user-existing';
    passwordField.value = 'hunter2';

    attachNewCredentialCapture(passwordField, usernameField);
    submit(form);
    await flushAsync();

    expect(fakeChrome.runtime.sendMessage).not.toHaveBeenCalledWith(
      expect.objectContaining({ type: VAULT_EDIT_ENQUEUE_MESSAGE }),
    );
  });

  it('não propõe com senha vazia', async () => {
    const fakeChrome = buildFakeChrome([]);
    globalThis.chrome = fakeChrome as unknown as typeof chrome;
    const { form, usernameField, passwordField } = buildSignupForm();
    usernameField.value = 'user-empty';
    passwordField.value = '';

    attachNewCredentialCapture(passwordField, usernameField);
    submit(form);
    await flushAsync();

    expect(fakeChrome.runtime.sendMessage).not.toHaveBeenCalled();
  });

  it('formulário com senha+confirmar-senha gera só uma proposta por submit', async () => {
    const fakeChrome = buildFakeChrome([]);
    globalThis.chrome = fakeChrome as unknown as typeof chrome;
    const { form, usernameField, passwordField } = buildSignupForm();
    const confirmField = document.createElement('input');
    confirmField.type = 'password';
    form.appendChild(confirmField);
    usernameField.value = 'user-confirm';
    passwordField.value = 'hunter2';
    confirmField.value = 'hunter2';

    attachNewCredentialCapture(passwordField, usernameField);
    attachNewCredentialCapture(confirmField, usernameField);
    submit(form);
    await flushAsync();

    const enqueueCalls = fakeChrome.runtime.sendMessage.mock.calls.filter(
      ([message]) => message.type === VAULT_EDIT_ENQUEUE_MESSAGE,
    );
    expect(enqueueCalls).toHaveLength(1);
  });

  it('só propõe na primeira tentativa quando o mesmo hostname+username é submetido de novo', async () => {
    const fakeChrome = buildFakeChrome([]);
    globalThis.chrome = fakeChrome as unknown as typeof chrome;
    const { form, usernameField, passwordField } = buildSignupForm();
    usernameField.value = 'user-retry';
    passwordField.value = 'wrong-password';

    attachNewCredentialCapture(passwordField, usernameField);
    submit(form);
    await flushAsync();

    passwordField.value = 'hunter2';
    submit(form);
    await flushAsync();

    const enqueueCalls = fakeChrome.runtime.sendMessage.mock.calls.filter(
      ([message]) => message.type === VAULT_EDIT_ENQUEUE_MESSAGE,
    );
    expect(enqueueCalls).toHaveLength(1);
    expect(enqueueCalls[0][0].proposal?.password).toBe('wrong-password');
  });
});

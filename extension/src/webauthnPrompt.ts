// Prompt de confirmação antes de assinar um login com passkey (Sessão 132)
// — mesmo padrão de Shadow DOM `closed` + tokens embutidos de
// `autofill/overlay.ts`, mas centrado na tela (não ancorado a um campo:
// `navigator.credentials.get()` não tem necessariamente um input visível
// perto). Nunca assina sem esse clique — decisão confirmada com o dono do
// projeto, preserva uma noção de presença do usuário (o WebAuthn nativo
// pede toque no sensor; isto é o equivalente possível dentro da extensão).
const PROMPT_STYLE = `
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 2147483647;
    font-family: 'Inter', system-ui, sans-serif;
  }
  .box {
    background: #111820;
    border: 1px solid #1f2630;
    border-radius: 12px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
    padding: 20px;
    width: 100%;
    max-width: 320px;
    color: #e6edf3;
  }
  .title {
    font-size: 14px;
    font-weight: 600;
    margin: 0 0 8px;
  }
  .site {
    color: #4dd0e1;
  }
  .subtitle {
    font-size: 12px;
    color: #9fb1c2;
    margin: 0 0 16px;
  }
  .actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
  }
  button {
    font-family: inherit;
    font-size: 13px;
    border-radius: 6px;
    padding: 6px 14px;
    cursor: pointer;
    border: 1px solid #1f2630;
    background: transparent;
    color: #9fb1c2;
  }
  button.approve {
    background: #4dd0e1;
    border-color: #4dd0e1;
    color: #0b0f14;
    font-weight: 600;
  }
`;

/** Resolve `true` se o usuário clicar em Approve, `false` em Cancel ou clique fora. */
export function showWebauthnConfirmPrompt(site: string): Promise<boolean> {
  return new Promise((resolve) => {
    const host = document.createElement('div');
    document.documentElement.appendChild(host);
    const shadow = host.attachShadow({ mode: 'closed' });

    const style = document.createElement('style');
    style.textContent = PROMPT_STYLE;
    shadow.appendChild(style);

    const overlay = document.createElement('div');
    overlay.className = 'overlay';

    const box = document.createElement('div');
    box.className = 'box';

    const title = document.createElement('p');
    title.className = 'title';
    title.textContent = 'Sign in with your TruthID passkey?';

    const subtitle = document.createElement('p');
    subtitle.className = 'subtitle';
    const siteSpan = document.createElement('span');
    siteSpan.className = 'site';
    siteSpan.textContent = site;
    subtitle.append('Requested by ', siteSpan);

    const actions = document.createElement('div');
    actions.className = 'actions';

    function finish(result: boolean): void {
      host.remove();
      resolve(result);
    }

    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.textContent = 'Cancel';
    cancelBtn.addEventListener('click', () => finish(false));

    const approveBtn = document.createElement('button');
    approveBtn.type = 'button';
    approveBtn.className = 'approve';
    approveBtn.textContent = 'Sign in';
    approveBtn.addEventListener('click', () => finish(true));

    actions.append(cancelBtn, approveBtn);
    box.append(title, subtitle, actions);
    overlay.appendChild(box);
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) finish(false);
    });
    shadow.appendChild(overlay);
  });
}

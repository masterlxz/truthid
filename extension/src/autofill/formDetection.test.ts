// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest';
import { findLoginFieldPairs } from './formDetection';

function setBody(html: string): void {
  document.body.innerHTML = html;
}

describe('findLoginFieldPairs', () => {
  beforeEach(() => {
    setBody('');
  });

  it('acha o par usuário/senha dentro de um <form>', () => {
    setBody(`
      <form>
        <input type="text" name="user" />
        <input type="password" name="pass" />
      </form>
    `);

    const pairs = findLoginFieldPairs(document);

    expect(pairs).toHaveLength(1);
    expect(pairs[0].passwordField.name).toBe('pass');
    expect(pairs[0].usernameField?.name).toBe('user');
  });

  it('acha o campo de usuário via autocomplete mesmo sem type=text/email', () => {
    setBody(`
      <form>
        <input autocomplete="username" name="handle" />
        <input type="password" name="pass" />
      </form>
    `);

    const pairs = findLoginFieldPairs(document);

    expect(pairs[0].usernameField?.name).toBe('handle');
  });

  it('acha o par sem <form> nenhum (comum em SPAs) via ancestral genérico', () => {
    setBody(`
      <div class="login-widget">
        <input type="email" name="email" />
        <input type="password" name="pass" />
      </div>
    `);

    const pairs = findLoginFieldPairs(document);

    expect(pairs).toHaveLength(1);
    expect(pairs[0].usernameField?.name).toBe('email');
  });

  it('retorna usernameField null quando não há candidato razoável', () => {
    setBody(`
      <form>
        <input type="password" name="pass" />
      </form>
    `);

    const pairs = findLoginFieldPairs(document);

    expect(pairs).toHaveLength(1);
    expect(pairs[0].usernameField).toBeNull();
  });

  it('ignora campo de senha escondido (display:none)', () => {
    setBody(`
      <form>
        <input type="text" name="user" />
        <input type="password" name="pass" style="display:none" />
      </form>
    `);

    expect(findLoginFieldPairs(document)).toHaveLength(0);
  });

  it('ignora campo de senha com o atributo hidden', () => {
    setBody(`
      <form>
        <input type="text" name="user" />
        <input type="password" name="pass" hidden />
      </form>
    `);

    expect(findLoginFieldPairs(document)).toHaveLength(0);
  });

  it('não processa o mesmo campo de senha duas vezes (WeakSet)', () => {
    setBody(`
      <form>
        <input type="text" name="user" />
        <input type="password" name="pass" />
      </form>
    `);

    expect(findLoginFieldPairs(document)).toHaveLength(1);
    // Segunda varredura do mesmo documento (simula o MutationObserver
    // disparando de novo) — não deve reprocessar o mesmo campo.
    expect(findLoginFieldPairs(document)).toHaveLength(0);
  });

  it('detecta múltiplos formulários de login na mesma página', () => {
    setBody(`
      <form id="a"><input type="text" name="u1" /><input type="password" name="p1" /></form>
      <form id="b"><input type="text" name="u2" /><input type="password" name="p2" /></form>
    `);

    const pairs = findLoginFieldPairs(document);

    expect(pairs).toHaveLength(2);
    expect(pairs.map((p) => p.usernameField?.name)).toEqual(['u1', 'u2']);
  });
});

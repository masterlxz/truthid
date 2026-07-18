import { describe, expect, it } from 'vitest';
import { matchesOrigin } from './entryMatching';

describe('matchesOrigin', () => {
  it('bate por hostname exato de entry.url', () => {
    expect(matchesOrigin({ site: '', url: 'https://github.com/login' }, 'github.com')).toBe(true);
  });

  it('bate por entry.site quando entry.url está vazio', () => {
    expect(matchesOrigin({ site: 'github.com', url: '' }, 'github.com')).toBe(true);
  });

  it('bate quando a página atual é um subdomínio da entrada', () => {
    expect(matchesOrigin({ site: 'github.com', url: '' }, 'www.github.com')).toBe(true);
  });

  it('bate quando a entrada é um subdomínio da página atual', () => {
    expect(matchesOrigin({ site: 'www.github.com', url: '' }, 'github.com')).toBe(true);
  });

  it('não bate com domínio diferente', () => {
    expect(matchesOrigin({ site: 'github.com', url: '' }, 'gitlab.com')).toBe(false);
  });

  it('não bate por sufixo textual sem separador de subdomínio (evita falso positivo)', () => {
    expect(matchesOrigin({ site: 'github.com', url: '' }, 'notgithub.com')).toBe(false);
  });

  it('entry.url inválida não quebra — cai pro fallback de entry.site', () => {
    expect(matchesOrigin({ site: 'github.com', url: 'not a url' }, 'github.com')).toBe(true);
  });

  it('nem entry.site nem entry.url preenchidos — não bate com nada', () => {
    expect(matchesOrigin({ site: '', url: '' }, 'github.com')).toBe(false);
  });

  it('comparação não diferencia maiúsculas/minúsculas', () => {
    expect(matchesOrigin({ site: 'GitHub.com', url: '' }, 'github.com')).toBe(true);
  });
});

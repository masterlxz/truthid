// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest';
import { setNativeValue } from './fillField';

describe('setNativeValue', () => {
  it('define o valor do input', () => {
    const input = document.createElement('input');
    setNativeValue(input, 'hunter2');
    expect(input.value).toBe('hunter2');
  });

  it('dispara os eventos input e change (bubbling)', () => {
    const input = document.createElement('input');
    document.body.appendChild(input);

    const inputHandler = vi.fn();
    const changeHandler = vi.fn();
    input.addEventListener('input', inputHandler);
    input.addEventListener('change', changeHandler);

    setNativeValue(input, 'hunter2');

    expect(inputHandler).toHaveBeenCalledTimes(1);
    expect(changeHandler).toHaveBeenCalledTimes(1);
  });

  it('usa o setter nativo — funciona mesmo com um setter customizado na instância (padrão React)', () => {
    const input = document.createElement('input');
    let interceptedValue: string | null = null;

    // Mimetiza o que React faz: substitui o setter de `value` na
    // *instância* (não no protótipo) pra rastrear mudanças "não confiáveis".
    // setNativeValue precisa contornar isso via o setter do protótipo.
    Object.defineProperty(input, 'value', {
      configurable: true,
      get() {
        return interceptedValue ?? '';
      },
      set(v: string) {
        interceptedValue = `intercepted:${v}`;
      },
    });

    setNativeValue(input, 'hunter2');

    // O setter nativo do protótipo escreve no slot real do elemento,
    // ignorando o setter customizado da instância.
    const prototype = Object.getPrototypeOf(input) as HTMLInputElement;
    const nativeGetter = Object.getOwnPropertyDescriptor(prototype, 'value')?.get;
    expect(nativeGetter?.call(input)).toBe('hunter2');
  });
});

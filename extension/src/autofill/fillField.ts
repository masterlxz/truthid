/**
 * Preenche um `<input>` via o setter nativo de `HTMLInputElement.prototype`
 * em vez de atribuir `.value` direto. Atribuição direta é invisível pro
 * `onChange`/estado controlado de frameworks como React (eles substituem o
 * setter de `value` na instância, mas o valor "de verdade" só muda quando o
 * setter *nativo* do protótipo roda) — sem isso, o campo mostraria o valor
 * preenchido visualmente, mas o framework acharia que ainda está vazio e
 * rejeitaria o submit. Truque padrão usado por todo gerenciador de senha.
 */
export function setNativeValue(input: HTMLInputElement, value: string): void {
  const prototype = Object.getPrototypeOf(input) as HTMLInputElement;
  const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
  descriptor?.set?.call(input, value);

  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
}

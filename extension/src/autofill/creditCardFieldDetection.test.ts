// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest';
import { findCreditCardFieldGroups } from './creditCardFieldDetection';

function setBody(html: string): void {
  document.body.innerHTML = html;
}

describe('findCreditCardFieldGroups', () => {
  beforeEach(() => {
    setBody('');
  });

  it('acha um grupo de cartão dentro de um <form>', () => {
    setBody(`
      <form>
        <input autocomplete="cc-name" name="holder" />
        <input autocomplete="cc-number" name="number" />
        <input autocomplete="cc-exp" name="exp" />
        <input autocomplete="cc-csc" name="cvv" />
      </form>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.cardHolderName?.getAttribute('name')).toBe('holder');
    expect(groups[0].fields.cardNumber?.getAttribute('name')).toBe('number');
    expect(groups[0].fields.expiryDate?.getAttribute('name')).toBe('exp');
    expect(groups[0].fields.cvv?.getAttribute('name')).toBe('cvv');
  });

  it('reconhece mês/ano de validade como campos separados', () => {
    setBody(`
      <form>
        <input autocomplete="cc-number" name="number" />
        <input autocomplete="cc-exp-month" name="expMonth" />
        <input autocomplete="cc-exp-year" name="expYear" />
      </form>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.expiryMonth?.getAttribute('name')).toBe('expMonth');
    expect(groups[0].fields.expiryYear?.getAttribute('name')).toBe('expYear');
    expect(groups[0].fields.expiryDate).toBeUndefined();
  });

  it('pega só o último token quando autocomplete tem hints extras', () => {
    setBody(`
      <form>
        <input autocomplete="billing cc-number" name="number" />
        <input autocomplete="billing cc-csc" name="cvv" />
      </form>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.cardNumber?.getAttribute('name')).toBe('number');
    expect(groups[0].fields.cvv?.getAttribute('name')).toBe('cvv');
  });

  it('ignora campo isolado (só 1 token reconhecido) — não é sinal confiável de cartão', () => {
    setBody(`
      <form>
        <input autocomplete="cc-csc" name="unrelated" />
      </form>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(0);
  });

  it('ignora campos escondidos', () => {
    setBody(`
      <form>
        <input autocomplete="cc-number" name="number" hidden />
        <input autocomplete="cc-csc" name="cvv" hidden />
      </form>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(0);
  });

  it('não reprocessa o mesmo campo numa segunda varredura (dedupe)', () => {
    setBody(`
      <form>
        <input autocomplete="cc-number" name="number" />
        <input autocomplete="cc-csc" name="cvv" />
      </form>
    `);

    const first = findCreditCardFieldGroups(document);
    const second = findCreditCardFieldGroups(document);

    expect(first).toHaveLength(1);
    expect(second).toHaveLength(0);
  });

  it('agrupa cartão e endereço em grupos separados quando os escopos diferem', () => {
    setBody(`
      <div class="card-widget">
        <input autocomplete="cc-number" name="number" />
        <input autocomplete="cc-csc" name="cvv" />
      </div>
      <div class="address-widget">
        <input autocomplete="street-address" name="street" />
        <input autocomplete="postal-code" name="zip" />
      </div>
    `);

    const groups = findCreditCardFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.cardNumber).toBeDefined();
  });
});

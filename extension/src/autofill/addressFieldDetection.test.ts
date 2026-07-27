// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest';
import { findAddressFieldGroups } from './addressFieldDetection';

function setBody(html: string): void {
  document.body.innerHTML = html;
}

describe('findAddressFieldGroups', () => {
  beforeEach(() => {
    setBody('');
  });

  it('acha um grupo de endereço dentro de um <form>', () => {
    setBody(`
      <form>
        <input autocomplete="name" name="fullName" />
        <input autocomplete="street-address" name="street" />
        <input autocomplete="address-level2" name="city" />
        <input autocomplete="address-level1" name="state" />
        <input autocomplete="postal-code" name="zip" />
        <input autocomplete="country" name="country" />
      </form>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.fullName?.getAttribute('name')).toBe('fullName');
    expect(groups[0].fields.street?.getAttribute('name')).toBe('street');
    expect(groups[0].fields.city?.getAttribute('name')).toBe('city');
    expect(groups[0].fields.state?.getAttribute('name')).toBe('state');
    expect(groups[0].fields.zipCode?.getAttribute('name')).toBe('zip');
    expect(groups[0].fields.country?.getAttribute('name')).toBe('country');
  });

  it('reconhece <select> com autocomplete de estado/país', () => {
    setBody(`
      <form>
        <input autocomplete="street-address" name="street" />
        <select autocomplete="address-level1" name="state"></select>
        <select autocomplete="country" name="country"></select>
      </form>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.state?.tagName).toBe('SELECT');
    expect(groups[0].fields.country?.tagName).toBe('SELECT');
  });

  it('pega só o último token quando autocomplete tem hints extras', () => {
    setBody(`
      <form>
        <input autocomplete="shipping address-line1" name="street" />
        <input autocomplete="shipping postal-code" name="zip" />
      </form>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(1);
    expect(groups[0].fields.street?.getAttribute('name')).toBe('street');
    expect(groups[0].fields.zipCode?.getAttribute('name')).toBe('zip');
  });

  it('ignora campo isolado (só 1 token reconhecido) — não é sinal confiável de endereço', () => {
    setBody(`
      <form>
        <input autocomplete="tel" name="newsletter-phone" />
      </form>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(0);
  });

  it('ignora campos escondidos', () => {
    setBody(`
      <form>
        <input autocomplete="street-address" name="street" hidden />
        <input autocomplete="postal-code" name="zip" hidden />
      </form>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(0);
  });

  it('não reprocessa o mesmo campo numa segunda varredura (dedupe)', () => {
    setBody(`
      <form>
        <input autocomplete="street-address" name="street" />
        <input autocomplete="postal-code" name="zip" />
      </form>
    `);

    const first = findAddressFieldGroups(document);
    const second = findAddressFieldGroups(document);

    expect(first).toHaveLength(1);
    expect(second).toHaveLength(0);
  });

  it('agrupa campos de endereço e cartão em grupos separados quando os escopos diferem', () => {
    setBody(`
      <div class="address-widget">
        <input autocomplete="street-address" name="street" />
        <input autocomplete="postal-code" name="zip" />
      </div>
      <div class="other-widget">
        <input autocomplete="address-level2" name="city2" />
        <input autocomplete="address-level1" name="state2" />
      </div>
    `);

    const groups = findAddressFieldGroups(document);

    expect(groups).toHaveLength(2);
  });
});

import { describe, expect, it } from 'vitest';
import { decodeAlarmName, encodeAlarmName } from './autofillDeadDropAlarm';

describe('encodeAlarmName / decodeAlarmName', () => {
  it('round-trip preserva sessionId e expiresAtMs', () => {
    const name = encodeAlarmName('abc123', 1_800_000_000_000);
    expect(decodeAlarmName(name)).toEqual({
      sessionId: 'abc123',
      expiresAtMs: 1_800_000_000_000,
    });
  });

  it('devolve null pra nomes de alarme que não são deste esquema', () => {
    expect(decodeAlarmName('truthid-vault-session-expiry')).toBeNull();
    expect(decodeAlarmName('truthid-dead-drop-poll')).toBeNull();
    expect(decodeAlarmName('something-else')).toBeNull();
  });

  it('devolve null pra nome malformado com o prefixo certo', () => {
    expect(decodeAlarmName('truthid-autofill-dead-drop-poll:semseparador')).toBeNull();
    expect(decodeAlarmName('truthid-autofill-dead-drop-poll::123')).toBeNull();
    expect(decodeAlarmName('truthid-autofill-dead-drop-poll:abc:naoenumero')).toBeNull();
  });
});

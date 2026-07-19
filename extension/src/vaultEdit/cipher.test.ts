import { describe, expect, it } from 'vitest';
import { decryptVaultEditContent, deriveVaultEditContentKey, encryptVaultEditContent } from './cipher';

describe('vaultEdit/cipher', () => {
  it('roundtrip: cifra e decifra de volta o mesmo plaintext', async () => {
    const sessionId = 'a1b2c3d4e5f6071829'.padEnd(32, '0');
    const key = deriveVaultEditContentKey(sessionId);
    const plaintext = new TextEncoder().encode(JSON.stringify({ site: 'example.com' }));

    const blob = await encryptVaultEditContent(plaintext, key);
    const decrypted = await decryptVaultEditContent(blob, key);

    expect(new TextDecoder().decode(decrypted)).toBe(JSON.stringify({ site: 'example.com' }));
  });

  it('chave errada (sessionId diferente) falha ao decifrar', async () => {
    const keyA = deriveVaultEditContentKey('a'.repeat(32));
    const keyB = deriveVaultEditContentKey('b'.repeat(32));
    const blob = await encryptVaultEditContent(new TextEncoder().encode('hello'), keyA);

    await expect(decryptVaultEditContent(blob, keyB)).rejects.toThrow();
  });

  it('blob curto demais lança', async () => {
    const key = deriveVaultEditContentKey('a'.repeat(32));
    await expect(decryptVaultEditContent(new Uint8Array(5), key)).rejects.toThrow(
      'too short',
    );
  });

  it('mesmo sessionId sempre deriva a mesma chave (determinístico)', () => {
    const a = deriveVaultEditContentKey('c'.repeat(32));
    const b = deriveVaultEditContentKey('c'.repeat(32));
    expect(a).toEqual(b);
  });
});

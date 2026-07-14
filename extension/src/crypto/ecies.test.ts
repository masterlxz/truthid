import { describe, expect, it } from 'vitest';
import { decrypt, encrypt } from './ecies';
import { secp256k1 } from '@noble/curves/secp256k1';

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function bytesToUtf8(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function base64ToBytes(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

describe('ECIES encrypt/decrypt round-trip (self)', () => {
  it('decrypt(encrypt(x)) returns x', async () => {
    const recipientPriv = secp256k1.utils.randomPrivateKey();
    const recipientPub = secp256k1.getPublicKey(recipientPriv, true);
    const recipientPubHex = Array.from(recipientPub, (b) =>
      b.toString(16).padStart(2, '0'),
    ).join('');

    const plaintext = new TextEncoder().encode('hello from the extension');
    const blob = await encrypt(plaintext, recipientPubHex);
    const decrypted = await decrypt(blob, recipientPriv);

    expect(bytesToUtf8(decrypted)).toBe('hello from the extension');
  });

  it('each encrypt call uses a fresh ephemeral key', async () => {
    const recipientPriv = secp256k1.utils.randomPrivateKey();
    const recipientPub = secp256k1.getPublicKey(recipientPriv, true);
    const recipientPubHex = Array.from(recipientPub, (b) =>
      b.toString(16).padStart(2, '0'),
    ).join('');
    const plaintext = new TextEncoder().encode('same input');

    const blobA = await encrypt(plaintext, recipientPubHex);
    const blobB = await encrypt(plaintext, recipientPubHex);

    expect(blobA).not.toEqual(blobB);
  });

  it('fails to decrypt with the wrong private key', async () => {
    const recipientPriv = secp256k1.utils.randomPrivateKey();
    const wrongPriv = secp256k1.utils.randomPrivateKey();
    const recipientPub = secp256k1.getPublicKey(recipientPriv, true);
    const recipientPubHex = Array.from(recipientPub, (b) =>
      b.toString(16).padStart(2, '0'),
    ).join('');

    const blob = await encrypt(new TextEncoder().encode('secret'), recipientPubHex);

    await expect(decrypt(blob, wrongPriv)).rejects.toThrow();
  });
});

describe('vetor cruzado fixo — interoperabilidade com Rust/Dart', () => {
  // Mesmo trio usado em:
  //   desktop/src-tauri/src/lib.rs::dart_produced_blob_decrypts_correctly
  //   mobile/test/services/ecies_service_test.dart
  // Os três decifram o mesmo blob (produzido uma vez pelo EciesService.encrypt
  // real do Dart) e conferem o mesmo plaintext — prova interoperabilidade
  // determinística entre as 3 linguagens sem precisar de dois dispositivos
  // reais.
  const recipientPrivateKeyHex =
    'ebea44b99557c83965e6152a1393a5c6d74fe114f0a626f51bb2349e815136b2';
  const blobBase64 =
    'AqQAXxG3rw53DVihUXbTzqHcENoLZGbHFsnNHPFvZduk0FF00QwiZMLWLCs8q19CzAj4kYiWXr1jUTn0tUxh1ibNVbwPQiCSBZAJdH1eqE86qT1Na5ytsA==';
  const expectedPlaintext = 'truthid-vault-entry-fixture';

  it('decrypts the fixed cross-language blob correctly', async () => {
    const privBytes = hexToBytes(recipientPrivateKeyHex);
    const blob = base64ToBytes(blobBase64);

    const plaintext = await decrypt(blob, privBytes);

    expect(bytesToUtf8(plaintext)).toBe(expectedPlaintext);
  });
});

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/pin_content_cipher.dart' show derivePinContentKey;
import 'package:truthid_sdk/src/internal/vault_edit_content_cipher.dart';

void main() {
  const sessionId = '000102030405060708090a0b0c0d0e0f';

  test('deriveVaultEditContentKey is deterministic for the same sessionId', () {
    expect(deriveVaultEditContentKey(sessionId), deriveVaultEditContentKey(sessionId));
  });

  test('deriveVaultEditContentKey differs from a different sessionId', () {
    expect(
      deriveVaultEditContentKey(sessionId),
      isNot(deriveVaultEditContentKey('0f0e0d0c0b0a09080706050403020100')),
    );
  });

  test('deriveVaultEditContentKey differs from /pin\'s content key (domain separation)', () {
    // Mesmo sessionId, dois protocolos — só o salt do HKDF muda; garante que
    // um QR de /pin e um de vault-edit com o mesmo sessionId (coincidência,
    // não deveria acontecer, mas não pode ser explorável) nunca decifram um
    // com a chave do outro.
    expect(deriveVaultEditContentKey(sessionId), isNot(derivePinContentKey(sessionId)));
  });

  test('encryptVaultEditContent produces a genuinely decryptable AES-256-GCM blob', () async {
    final key = deriveVaultEditContentKey(sessionId);
    final plaintext = Uint8List.fromList(
      '{"site":"example.com","username":"alice","password":"hunter2"}'.codeUnits,
    );

    final blob = await encryptVaultEditContent(plaintext, key);

    // Manually unpack the blob the same way the Device's receiver does
    // (nonce(12) || ciphertext || tag(16)) and decrypt with the raw
    // `cryptography` package, independent of any SDK decrypt helper.
    final nonce = blob.sublist(0, 12);
    final rest = blob.sublist(12);
    final mac = rest.sublist(rest.length - 16);
    final ciphertext = rest.sublist(0, rest.length - 16);

    final decrypted = await AesGcm.with256bits().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
    );

    expect(Uint8List.fromList(decrypted), plaintext);
  });

  test('produces a different blob on every call (fresh nonce)', () async {
    final key = deriveVaultEditContentKey(sessionId);
    final plaintext = Uint8List.fromList('same proposal'.codeUnits);

    final blob1 = await encryptVaultEditContent(plaintext, key);
    final blob2 = await encryptVaultEditContent(plaintext, key);

    expect(blob1, isNot(blob2));
  });
}

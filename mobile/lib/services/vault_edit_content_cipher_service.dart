import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';

/// Cifra simétrica da proposta de credencial nova transportada da extensão
/// pro celular na fase 1 do `/truthid/v1/vault-edit` cross-device (Sessão
/// 134). Mesma técnica de [decryptPinContent]/`pin_content_cipher_service.
/// dart` — chave AES-256 derivada via HKDF do `sessionId` (só conhecido por
/// quem viu o QR, faz o papel de segredo compartilhado). Salt/info
/// **diferentes** dos usados pelo `/pin` — nunca reusar a mesma derivação
/// entre protocolos (domain separation). Espelha exatamente
/// `extension/src/vaultEdit/cipher.ts`.
const _vaultEditHkdfSalt = 'TruthID Vault Edit Content';
const _vaultEditHkdfInfo = 'content-key-v1';

const int _nonceLen = 12;

/// Deriva a chave AES-256 da fase 1 a partir do `sessionId` (hex).
Uint8List deriveVaultEditContentKey(String sessionIdHex) {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  return hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_vaultEditHkdfSalt),
    info: utf8.encode(_vaultEditHkdfInfo),
    length: 32,
  );
}

/// Decifra o blob recebido na fase 1. Formato: `nonce(12) || ciphertext+tag`
/// (AES-256-GCM, mesmo formato que `Web Crypto`'s AES-GCM produz do lado da
/// extensão). Lança `FormatException` se o blob for curto demais ou o MAC
/// não bater (sessionId errado ou conteúdo corrompido/adulterado).
Future<Uint8List> decryptVaultEditContent(Uint8List blob, Uint8List key) async {
  if (blob.length < _nonceLen + 16) {
    throw const FormatException('vault edit content blob too short or corrupted');
  }
  final nonce = blob.sublist(0, _nonceLen);
  final rest = blob.sublist(_nonceLen);
  final mac = rest.sublist(rest.length - 16);
  final ciphertext = rest.sublist(0, rest.length - 16);

  final secretKey = SecretKey(key);
  try {
    final plaintext = await AesGcm.with256bits().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
    return Uint8List.fromList(plaintext);
  } on SecretBoxAuthenticationError {
    throw const FormatException(
      'failed to decrypt vault edit content (wrong session or corrupted data)',
    );
  }
}

/// Cifra um blob no mesmo formato que [decryptVaultEditContent] espera. Só
/// existe pros testes deste módulo simularem o lado extensão (que já tem sua
/// própria implementação em TypeScript, `cipher.ts`).
Future<Uint8List> encryptVaultEditContent(Uint8List plaintext, Uint8List key) async {
  final secretKey = SecretKey(key);
  final secretBox = await AesGcm.with256bits().encrypt(
    plaintext,
    secretKey: secretKey,
  );
  return Uint8List.fromList([
    ...secretBox.nonce,
    ...secretBox.cipherText,
    ...secretBox.mac.bytes,
  ]);
}

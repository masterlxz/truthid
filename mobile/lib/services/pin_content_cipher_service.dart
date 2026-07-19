import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';

/// Cifra simétrica do conteúdo a pinar, transportado do app requisitante pro
/// celular na fase 1 do `/pin` cross-device (ver `PinApprovalScreen`).
/// Diferente da fase 2 (resultado do celular pro requisitante, que usa ECIES
/// contra o `ephemeralPubKey` do QR), nesta direção nenhuma das duas pontas
/// tem a chave pública da outra — o requisitante gerou o QR antes do celular
/// entrar em cena, e o celular não expõe nenhuma chave própria no payload.
/// Resolvido com uma chave simétrica derivada deterministicamente do
/// `sessionId` via HKDF, mesmo padrão que `IpnsKeyService` já usa pra
/// derivar a chave IPNS do dead-drop a partir do `sessionId` — o `sessionId`
/// (só conhecido por quem viu o QR) já faz o papel de segredo compartilhado.
const _pinContentHkdfSalt = 'TruthID Pin Content';
const _pinContentHkdfInfo = 'content-key-v1';

const int _nonceLen = 12;

/// Deriva a chave AES-256 da fase 1 a partir do `sessionId` (hex). Nunca
/// reusar o `salt`/`info` da derivação IPNS (`ipns_key_service.dart`) —
/// contextos diferentes, domain separation.
Uint8List derivePinContentKey(String sessionIdHex) {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  return hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_pinContentHkdfSalt),
    info: utf8.encode(_pinContentHkdfInfo),
    length: 32,
  );
}

/// Decifra o blob recebido na fase 1. Formato: `nonce(12) || ciphertext+tag`
/// (AES-256-GCM, mesmo algoritmo que `BackupCipherService` já usa — aqui sem
/// PBKDF2, a chave já vem pronta de [derivePinContentKey]). Lança
/// `FormatException` se o blob for curto demais ou o MAC não bater (chave
/// errada ou conteúdo corrompido/adulterado).
Future<Uint8List> decryptPinContent(Uint8List blob, Uint8List key) async {
  if (blob.length < _nonceLen + 16) {
    throw const FormatException('pin content blob too short or corrupted');
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
      'failed to decrypt pin content (wrong session or corrupted data)',
    );
  }
}

/// Cifra um blob no mesmo formato que [decryptPinContent] espera. Só existe
/// pro lado requisitante (ainda não implementado em nenhum app — ver plano),
/// e pros testes deste módulo simularem esse lado enquanto ele não existe em
/// produção.
Future<Uint8List> encryptPinContent(Uint8List plaintext, Uint8List key) async {
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

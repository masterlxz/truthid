import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Gera códigos TOTP (RFC 6238) localmente, a partir do segredo cifrado no
/// Vault. Espelho funcional de `desktop/src/utils/totp.ts` — os dois lados
/// precisam produzir exatamente o mesmo código pro mesmo segredo/timestamp
/// (ver teste com vetor do RFC 6238 Apêndice B em `totp_service_test.dart`).
const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const _stepSeconds = 30;
const _digits = 6;

/// Decodifica uma string base32 (RFC 4648, sem exigir padding) em bytes.
Uint8List base32Decode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
  final bytes = <int>[];
  var bits = 0;
  var value = 0;

  for (final char in cleaned.split('')) {
    final idx = _base32Alphabet.indexOf(char);
    if (idx == -1) throw FormatException('Invalid base32 character: $char');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((value >> bits) & 0xff);
    }
  }

  return Uint8List.fromList(bytes);
}

/// Aceita um segredo base32 cru ou uma URI `otpauth://totp/...` (formato que
/// a maioria dos sites codifica no QR de configuração do 2FA) e devolve o
/// segredo base32 limpo. Lança `FormatException` se não conseguir extrair um
/// segredo usável.
String parseTotpSecret(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) throw const FormatException('TOTP secret is empty');

  if (trimmed.toLowerCase().startsWith('otpauth://')) {
    final uri = Uri.parse(trimmed);
    final secret = uri.queryParameters['secret'];
    if (secret == null || secret.isEmpty) {
      throw const FormatException('otpauth:// URI has no secret parameter');
    }
    return secret.toUpperCase();
  }

  final cleaned = trimmed.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(cleaned)) {
    throw const FormatException('Not a valid base32 TOTP secret');
  }
  return cleaned;
}

/// Segundos restantes na janela atual de 30s do TOTP.
int secondsRemaining(int unixSeconds) {
  return _stepSeconds - (unixSeconds % _stepSeconds);
}

/// Gera o código TOTP atual (RFC 6238) pra um segredo base32 num timestamp
/// unix dado. HMAC-SHA1 via `package:crypto`, mesma primitiva já usada em
/// `hkdf_util.dart` (com SHA-256).
String generateTotpCode(String secretBase32, int unixSeconds) {
  final keyBytes = base32Decode(secretBase32);
  final counter = unixSeconds ~/ _stepSeconds;

  final counterBytes = ByteData(8);
  counterBytes.setUint32(0, 0);
  counterBytes.setUint32(4, counter);

  final signature =
      crypto.Hmac(crypto.sha1, keyBytes).convert(counterBytes.buffer.asUint8List()).bytes;

  final offset = signature[signature.length - 1] & 0x0f;
  final binary = ((signature[offset] & 0x7f) << 24) |
      ((signature[offset + 1] & 0xff) << 16) |
      ((signature[offset + 2] & 0xff) << 8) |
      (signature[offset + 3] & 0xff);

  final code = binary % _pow10(_digits);
  return code.toString().padLeft(_digits, '0');
}

int _pow10(int n) {
  var result = 1;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

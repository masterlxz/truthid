import 'dart:convert';
import 'dart:typed_data';

// Base64url (RFC 4648 §5) sem padding — usado em toda a serialização de
// transação Arweave (owner/target/data_root/tags/signature/etc). Espelha
// wallet.rs/transaction.rs do cliente Arweave standalone do Desktop
// (desktop/src-tauri/src/arweave/), mesma divisão estrito/permissivo pelo
// mesmo motivo real: o decoder nativo do Dart (`base64Url`, testado contra
// o vetor abaixo) é tão estrito quanto o decoder Rust — rejeita bits
// residuais não-zero no último símbolo. Campos que o próprio cliente
// codifica devem sempre bater canonicamente (`b64UrlDecodeStrict`); campos
// que vêm de fora (ex.: o anchor devolvido por `GET /tx_anchor`) podem não
// ser canônicos bit-a-bit mesmo sendo base64url válido nos caracteres —
// achado real validando contra ArLocal, que devolve um anchor assim
// (vetor de teste: "vq1pzfxj6ba96uc9cyn3qj4hdspa0tlj5s04tfyi1w5" decodifica
// só no modo permissivo, para
// bead69cdfc63e9b6bdeae73d7329f7aa3e2176ca5ad2d963e6cd38b5fca2d70e).

String b64UrlEncode(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64UrlDecodeStrict(String s) {
  try {
    return base64Url.decode(base64Url.normalize(s));
  } on FormatException catch (e) {
    throw FormatException('base64url inválido (estrito): $s (${e.message})');
  }
}

// Decodifica ignorando bits residuais no último símbolo, em vez de exigir
// que sejam zero — equivalente a `decode_allow_trailing_bits(true)` da
// crate `base64` usada no Rust. Não existe essa opção no `base64Url`
// nativo do Dart, então isso decodifica manualmente: acumula 6 bits por
// caractere, extrai bytes completos assim que houver 8+ bits acumulados, e
// simplesmente descarta o que sobrar no final (nunca valida o valor desses
// bits sobrando) — permissivo por construção, não por configuração.
const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

final List<int> _lenientLookup = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    table[_alphabet.codeUnitAt(i)] = i;
  }
  return table;
}();

Uint8List b64UrlDecodeLenient(String s) {
  final bytes = <int>[];
  var buffer = 0;
  var bitsInBuffer = 0;
  for (final codeUnit in s.codeUnits) {
    if (codeUnit == 0x3D) continue; // '=' — padding, se presente, ignorado
    final value = codeUnit < 128 ? _lenientLookup[codeUnit] : -1;
    if (value == -1) {
      throw FormatException(
          'caractere base64url inválido: ${String.fromCharCode(codeUnit)} em $s');
    }
    buffer = (buffer << 6) | value;
    bitsInBuffer += 6;
    if (bitsInBuffer >= 8) {
      bitsInBuffer -= 8;
      bytes.add((buffer >> bitsInBuffer) & 0xFF);
    }
  }
  return Uint8List.fromList(bytes);
}

/// Converte um texto decimal de ETH (ex: "0.001", vindo direto do campo de
/// financiamento em CreateIdentityScreen) pra wei.
///
/// Achado real (P68, fatia 1): `EtherAmount.fromBase10String` do `web3dart`
/// tem um nome enganoso — apesar do nome, ela faz `BigInt.parse(amount)`
/// direto no texto inteiro, sem nenhum tratamento de ponto decimal. Passar
/// "0.001" pra ela lança `FormatException` na hora (`BigInt.parse` não
/// aceita ponto). Ela só serve pra um número JÁ inteiro na unidade dada (ex:
/// `fromBase10String(EtherUnit.wei, "1000000000000000")`), não pra um valor
/// fracionário de ETH como usuário digitaria. Esta função faz o parse
/// decimal de verdade.
BigInt parseEthToWei(String ethText) {
  final trimmed = ethText.trim();
  if (trimmed.isEmpty) return BigInt.zero;

  final negative = trimmed.startsWith('-');
  final unsigned = negative ? trimmed.substring(1) : trimmed;

  final parts = unsigned.split('.');
  if (parts.length > 2) {
    throw FormatException('invalid ETH amount: $ethText');
  }

  final whole = parts[0].isEmpty ? '0' : parts[0];
  var fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > 18) {
    throw FormatException(
        'too many decimal places for wei precision (max 18): $ethText');
  }
  fraction = fraction.padRight(18, '0');

  final wei = BigInt.parse(whole) * BigInt.from(10).pow(18) +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
  return negative ? -wei : wei;
}

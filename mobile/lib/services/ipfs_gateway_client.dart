import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

// Baixa um blob pelo CID a partir de gateways IPFS públicos — usado pelo
// VaultSyncService (13.8) pra buscar o vault cifrado publicado pelo Desktop.
// Só gateways HTTP públicos de leitura, sem autenticação — os provedores de
// pin configurados pelo usuário (Pinata/Filebase/Kubo, etc.) são escopo do
// Desktop (VaultSettings), não precisam ser consultados aqui pra ler.
class IpfsGatewayClient {
  IpfsGatewayClient({
    this.gateways = const [
      'https://ipfs.io/ipfs/',
      'https://dweb.link/ipfs/',
    ],
    this.timeout = const Duration(seconds: 15),
  });

  final List<String> gateways;
  final Duration timeout;

  // Tenta cada gateway em ordem, a primeira resposta 200 vence. Lança se
  // todos falharem (rede, timeout, ou status != 200), com um resumo do que
  // cada gateway retornou.
  Future<Uint8List> fetch(String cid) async {
    final errors = <String>[];
    for (final gateway in gateways) {
      try {
        return await _fetchFromGateway('$gateway$cid').timeout(timeout);
      } catch (e) {
        errors.add('$gateway: $e');
      }
    }
    throw Exception(
        'All IPFS gateways failed for cid $cid: ${errors.join('; ')}');
  }

  Future<Uint8List> _fetchFromGateway(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }
}

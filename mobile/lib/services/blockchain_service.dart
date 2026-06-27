import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Uint8List — ainda usado em SessionInfo.hash e nos hashes bytes32
import 'package:web3dart/web3dart.dart';

// Dados de uma sessão retornados pelo contrato
class SessionInfo {
  final Uint8List hash;
  final String devicePubKey;
  final DateTime createdAt;
  final bool isRevoked;

  const SessionInfo({
    required this.hash,
    required this.devicePubKey,
    required this.createdAt,
    required this.isRevoked,
  });

  // Converte os bytes do hash para string hex legível: "0xabcd1234..."
  String get hashHex =>
      '0x${hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

class BlockchainService {
  static const _rpcUrl = 'https://mainnet.base.org';
  static const _sessionRegistryAddress =
      '0x24074587a2aFB3aa5491361BB0a5eBee90797D1B';

  // ABI: apenas as funções que vamos usar (não precisa do ABI completo)
  static final _contract = DeployedContract(
    ContractAbi.fromJson('''[
      {
        "type": "function",
        "name": "getSessionsByIdentity",
        "inputs": [{"name": "identityId", "type": "uint256"}],
        "outputs": [{"name": "", "type": "bytes32[]"}],
        "stateMutability": "view"
      },
      {
        "type": "function",
        "name": "getSession",
        "inputs": [{"name": "hash", "type": "bytes32"}],
        "outputs": [{
          "name": "",
          "type": "tuple",
          "components": [
            {"name": "identityId", "type": "uint256"},
            {"name": "devicePubKey", "type": "address"},
            {"name": "createdAt", "type": "uint256"},
            {"name": "revoked", "type": "bool"},
            {"name": "exists", "type": "bool"}
          ]
        }],
        "stateMutability": "view"
      },
      {
        "type": "function",
        "name": "isSessionRevoked",
        "inputs": [{"name": "hash", "type": "bytes32"}],
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view"
      }
    ]''',
        'SessionRegistry'),
    EthereumAddress.fromHex(_sessionRegistryAddress),
  );

  // Faz uma leitura (eth_call) no contrato e retorna os valores decodificados.
  // eth_call é como um GET: não gasta gas, não precisa de wallet.
  Future<List<dynamic>> _ethCall(
      ContractFunction fn, List<dynamic> params) async {
    // 1. Codifica a chamada (nome da função + parâmetros) em binário ABI
    final callData = fn.encodeCall(params);
    final callDataHex =
        '0x${callData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

    // 2. Manda a requisição JSON-RPC para o nó
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_call',
        'params': [
          {'to': _sessionRegistryAddress, 'data': callDataHex},
          'latest',
        ],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception('RPC error: ${json['error']}');
      }

      // 3. Decodifica o resultado hex de volta para os tipos Dart
      // decodeReturnValues espera a string hex sem o '0x'
      final resultHex = (json['result'] as String).substring(2);
      return fn.decodeReturnValues(resultHex);
    } finally {
      client.close();
    }
  }

  Future<List<SessionInfo>> getSessionsForIdentity(BigInt identityId) async {
    // Passo 1: busca a lista de hashes de sessão da identidade
    final fn = _contract.function('getSessionsByIdentity');
    final result = await _ethCall(fn, [identityId]);
    final hashes = (result[0] as List<dynamic>).cast<Uint8List>();

    if (hashes.isEmpty) return [];

    // Passo 2: busca detalhes de todas as sessões em paralelo
    // Future.wait é como asyncio.gather() em Python — dispara todas as coroutines
    // ao mesmo tempo e aguarda todas terminarem, em vez de esperar uma por vez.
    final sessions = await Future.wait(
      hashes.map((hash) async {
        try {
          final getSessionFn = _contract.function('getSession');
          final isRevokedFn = _contract.function('isSessionRevoked');

          // Busca metadados e status de revogação em paralelo
          final results = await Future.wait([
            _ethCall(getSessionFn, [hash]),
            _ethCall(isRevokedFn, [hash]),
          ]);

          final tuple = results[0][0] as List<dynamic>;
          final exists = tuple[4] as bool;
          if (!exists) return null;

          return SessionInfo(
            hash: hash,
            devicePubKey: (tuple[1] as EthereumAddress).hex,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (tuple[2] as BigInt).toInt() * 1000,
            ),
            isRevoked: results[1][0] as bool,
          );
        } catch (_) {
          return null; // ignora sessões que falharam na leitura
        }
      }),
    );

    // whereType<T>() filtra nulls e faz o cast — equivale a
    // [s for s in sessions if s is not None] em Python
    return sessions.whereType<SessionInfo>().toList();
  }
}

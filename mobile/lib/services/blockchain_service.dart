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

// Dados de um device retornados pelo DeviceRegistry — usado pelo polling
// da tela de pareamento (ShowDeviceQrScreen) pra saber quando o desktop
// terminou de registrar este device.
class DeviceInfo {
  final BigInt identityId;
  final bool revoked;
  final bool exists;

  const DeviceInfo({
    required this.identityId,
    required this.revoked,
    required this.exists,
  });
}

class BlockchainService {
  static const _rpcUrl = 'https://mainnet.base.org';
  static const _sessionRegistryAddress =
      '0x24074587a2aFB3aa5491361BB0a5eBee90797D1B';
  static const _deviceRegistryAddress =
      '0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144';

  // ABI: apenas as funções que vamos usar (não precisa do ABI completo)
  static final _sessionContract = DeployedContract(
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

  static final _deviceContract = DeployedContract(
    ContractAbi.fromJson('''[
      {
        "type": "function",
        "name": "getDevice",
        "inputs": [{"name": "devicePubKey", "type": "address"}],
        "outputs": [{
          "name": "",
          "type": "tuple",
          "components": [
            {"name": "identityId", "type": "uint256"},
            {"name": "pubKey", "type": "address"},
            {"name": "label", "type": "string"},
            {"name": "addedAt", "type": "uint256"},
            {"name": "revoked", "type": "bool"},
            {"name": "exists", "type": "bool"}
          ]
        }],
        "stateMutability": "view"
      }
    ]''',
        'DeviceRegistry'),
    EthereumAddress.fromHex(_deviceRegistryAddress),
  );

  // Faz uma leitura (eth_call) no contrato e retorna os valores decodificados.
  // eth_call é como um GET: não gasta gas, não precisa de wallet.
  // contractAddress é parâmetro porque agora lemos de mais de um contrato
  // (SessionRegistry e DeviceRegistry) com a mesma função.
  Future<List<dynamic>> _ethCall(
      String contractAddress, ContractFunction fn, List<dynamic> params) async {
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
          {'to': contractAddress, 'data': callDataHex},
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
    final fn = _sessionContract.function('getSessionsByIdentity');
    final result = await _ethCall(_sessionRegistryAddress, fn, [identityId]);
    final hashes = (result[0] as List<dynamic>).cast<Uint8List>();

    if (hashes.isEmpty) return [];

    // Passo 2: busca detalhes de todas as sessões em paralelo
    // Future.wait é como asyncio.gather() em Python — dispara todas as coroutines
    // ao mesmo tempo e aguarda todas terminarem, em vez de esperar uma por vez.
    final sessions = await Future.wait(
      hashes.map((hash) async {
        try {
          final getSessionFn = _sessionContract.function('getSession');
          final isRevokedFn = _sessionContract.function('isSessionRevoked');

          // Busca metadados e status de revogação em paralelo
          final results = await Future.wait([
            _ethCall(_sessionRegistryAddress, getSessionFn, [hash]),
            _ethCall(_sessionRegistryAddress, isRevokedFn, [hash]),
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

  // Leitura usada no polling do pareamento: confirma se este device já foi
  // registrado pelo desktop. Retorna null se ainda não existe ou se a
  // chamada falhar (rede instável) — quem chama trata os dois casos igual:
  // "ainda não, tenta de novo na próxima rodada".
  Future<DeviceInfo?> getDevice(String address) async {
    try {
      final fn = _deviceContract.function('getDevice');
      final result = await _ethCall(
        _deviceRegistryAddress,
        fn,
        [EthereumAddress.fromHex(address)],
      );
      final tuple = result[0] as List<dynamic>;
      final exists = tuple[5] as bool;
      if (!exists) return null;

      return DeviceInfo(
        identityId: tuple[0] as BigInt,
        revoked: tuple[4] as bool,
        exists: true,
      );
    } catch (_) {
      return null;
    }
  }
}

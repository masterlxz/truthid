import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import '../contracts/abis.dart';
import '../utils/user_operation.dart' show entryPointV07Address;

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

// Dados de uma identidade retornados pelo IdentityRegistry — usado pela 14.9.5
// pra resolver o endereço da smart account (controller) que assina a UserOp.
class IdentityInfo {
  final BigInt id;
  final EthereumAddress controller;

  const IdentityInfo({required this.id, required this.controller});
}

class BlockchainService {
  static const _rpcUrl = 'https://mainnet.base.org';
  static const _sessionRegistryAddress =
      '0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65';
  static const _deviceRegistryAddress =
      '0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d';
  static const _identityRegistryAddress =
      '0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998';

  // Exposto publicamente — a 14.9.5 (SessionCreator) precisa deste endereço
  // como `dest` da chamada `TruthIDAccount.execute`.
  static const sessionRegistryAddress = _sessionRegistryAddress;

  // Único RPC configurado hoje é Base Mainnet (ver _rpcUrl acima) — por isso
  // um único chainId fixo, em vez de um mapa rede→chainId que nada usaria.
  static final chainId = BigInt.from(8453);

  static final _sessionContract = DeployedContract(
    ContractAbi.fromJson(sessionRegistryAbi, 'SessionRegistry'),
    EthereumAddress.fromHex(_sessionRegistryAddress),
  );

  static final _deviceContract = DeployedContract(
    ContractAbi.fromJson(deviceRegistryAbi, 'DeviceRegistry'),
    EthereumAddress.fromHex(_deviceRegistryAddress),
  );

  static final _identityContract = DeployedContract(
    ContractAbi.fromJson(identityRegistryAbi, 'IdentityRegistry'),
    EthereumAddress.fromHex(_identityRegistryAddress),
  );

  static final _entryPointContract = DeployedContract(
    ContractAbi.fromJson(entryPointAbi, 'EntryPoint'),
    EthereumAddress.fromHex(entryPointV07Address),
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

  // Resolve o @username da identidade via eth_getLogs no evento IdentityCreated.
  // O contrato não tem um getter id→username, então a única fonte é o log.
  // Retorna null se não encontrar (identidade não existe ou RPC falhou).
  Future<String?> getUsernameForIdentity(BigInt identityId) async {
    // keccak256("IdentityCreated(uint256,string,address)") — topic[0]
    final sigBytes = keccak256(
      Uint8List.fromList(utf8.encode('IdentityCreated(uint256,string,address)')));
    final eventTopic =
        '0x${sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    // topic[1] = indexed uint256 id, padded to 32 bytes
    final idTopic = '0x${identityId.toRadixString(16).padLeft(64, '0')}';

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_getLogs',
        'params': [
          {
            'address': _identityRegistryAddress,
            'topics': [eventTopic, idTopic],
          }
        ],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) return null;
      final logs = json['result'] as List<dynamic>;
      if (logs.isEmpty) return null;

      // ABI-decode the non-indexed `string username` from log.data.
      // Layout: [0-31] offset=0x20 | [32-63] length N | [64-64+N] UTF-8 bytes
      final dataHex =
          ((logs[0] as Map<String, dynamic>)['data'] as String).substring(2);
      final length = int.parse(dataHex.substring(64, 128), radix: 16);
      final strHex = dataHex.substring(128, 128 + length * 2);
      final strBytes = Uint8List.fromList(
        List.generate(strHex.length ~/ 2,
            (i) => int.parse(strHex.substring(i * 2, i * 2 + 2), radix: 16)),
      );
      return utf8.decode(strBytes);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
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

  // Resolve o controller (endereço da smart account, desde o débito #17) e o
  // identityId on-chain de uma identidade pelo @username — fonte de verdade
  // usada pela 14.9.5 pra saber quem é o `sender` da UserOperation.
  Future<IdentityInfo?> getIdentityByUsername(String username) async {
    try {
      final fn = _identityContract.function('getIdentity');
      final result = await _ethCall(_identityRegistryAddress, fn, [username]);
      final tuple = result[0] as List<dynamic>;
      final exists = tuple[3] as bool;
      if (!exists) return null;

      return IdentityInfo(
        id: tuple[0] as BigInt,
        controller: tuple[2] as EthereumAddress,
      );
    } catch (_) {
      return null;
    }
  }

  // Lê o nonce atual da smart account no EntryPoint (key=0 — nonce
  // sequencial simples, sem canais paralelos). Usado pela 14.9.5 antes de
  // montar uma UserOperation nova.
  Future<BigInt> getSmartAccountNonce(EthereumAddress sender) async {
    final fn = _entryPointContract.function('getNonce');
    final result = await _ethCall(
      entryPointV07Address,
      fn,
      [sender, BigInt.zero],
    );
    return result[0] as BigInt;
  }
}

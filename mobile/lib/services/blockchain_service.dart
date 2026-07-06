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
  // Endereços atualizados no redeploy de 2026-07-04 (corrige bug do
  // getAddress de 1 argumento no IdentityRegistry — ver PROJECT_STATE.md).
  static const _rpcUrl = 'https://mainnet.base.org';
  static const _sessionRegistryAddress =
      '0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776';
  static const _deviceRegistryAddress =
      '0x48e0862c43339f29ED850a59f5DBd08A4786EaDf';
  static const _identityRegistryAddress =
      '0x1313C576403F89eE265C880b33373d5DFB504cF2';

  // Exposto publicamente — a 14.9.5 (SessionCreator) precisa deste endereço
  // como `dest` da chamada `TruthIDAccount.execute`.
  static const sessionRegistryAddress = _sessionRegistryAddress;

  // Exposto publicamente — o SmartAccountActivityScanner (aba Wallet) precisa
  // deste endereço pra escanear os eventos DeviceRegistered/DeviceRevoked.
  static const deviceRegistryAddress = _deviceRegistryAddress;

  // Blocos de deploy na Base Mainnet (redeploy da Sessão 70, débito #28) —
  // mesmos valores já usados no Desktop (desktop/src/config/contracts.ts),
  // confirmados nos artefatos de broadcast do Foundry. Ponto de partida do
  // scan de histórico completo da aba Wallet.
  static const deviceRegistryDeployBlock = 48207828;
  static const sessionRegistryDeployBlock = 48207855;

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
    final callData = fn.encodeCall(params);
    final resultHex = await _ethCallRawHex(contractAddress, callData);
    // decodeReturnValues espera a string hex sem o '0x' (já removido em _ethCallRawHex)
    return fn.decodeReturnValues(resultHex);
  }

  // Faz o eth_call cru e devolve o hex do resultado (sem '0x'), sem decodificar.
  // Usado por _ethCall (decodifica via web3dart) e por chamadas que precisam
  // de decodificação manual (ver getIdentityByUsername).
  Future<String> _ethCallRawHex(
      String contractAddress, List<int> callData) async {
    final callDataHex =
        '0x${callData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

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

      return (json['result'] as String).substring(2);
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

  // Tamanho máximo de faixa de blocos por chamada eth_getLogs — RPCs públicos
  // (ex: sepolia.base.org) rejeitam faixas maiores com "query exceeds max
  // block range". Buscar sem fromBlock/toBlock faz o RPC assumir "latest"
  // (só o bloco mais recente) e nunca encontrar eventos antigos — por isso
  // não dá pra simplesmente omitir os dois, tem que paginar.
  static const _maxLogRangeBlocks = 2000;

  // Quantas faixas de _maxLogRangeBlocks percorrer pra trás a partir de
  // "latest" antes de desistir. 50 faixas ≈ 100k blocos ≈ ~55h de histórico
  // na Base (bloco a cada ~2s) — cobre confortavelmente uma identidade
  // pareada há pouco tempo (o caso de uso real: DevicesScreen chama isso
  // logo depois de descobrir um pareamento novo), sem escanear a chain
  // inteira desde o genesis.
  static const _maxLogLookbackChunks = 50;

  // Resolve o @username da identidade via eth_getLogs no evento IdentityCreated.
  // O contrato não tem um getter id→username, então a única fonte é o log.
  // Pagina pra trás a partir do bloco mais recente (ver _maxLogRangeBlocks/
  // _maxLogLookbackChunks) — identidades criadas há mais tempo que isso não
  // são encontradas (limitação conhecida, não um caso genérico de indexação).
  // Retorna null se não encontrar (identidade não existe, é antiga demais
  // pra essa janela, ou o RPC falhou).
  Future<String?> getUsernameForIdentity(BigInt identityId) async {
    // keccak256("IdentityCreated(uint256,string,address)") — topic[0]
    final sigBytes = keccak256(
      Uint8List.fromList(utf8.encode('IdentityCreated(uint256,string,address)')));
    final eventTopic =
        '0x${sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    // topic[1] = indexed uint256 id, padded to 32 bytes
    final idTopic = '0x${identityId.toRadixString(16).padLeft(64, '0')}';

    final latestBlock = await getLatestBlockNumber();
    if (latestBlock == null) return null;

    var toBlock = latestBlock;
    for (var chunk = 0; chunk < _maxLogLookbackChunks; chunk++) {
      final fromBlock =
          toBlock - _maxLogRangeBlocks + 1 > 0 ? toBlock - _maxLogRangeBlocks + 1 : 0;

      final logs = await _fetchIdentityCreatedLogs(
        eventTopic: eventTopic,
        idTopic: idTopic,
        fromBlock: fromBlock,
        toBlock: toBlock,
      );
      if (logs != null && logs.isNotEmpty) {
        return _decodeUsernameFromLog(logs.first as Map<String, dynamic>);
      }

      if (fromBlock == 0) break; // chegou no genesis, não tem mais o que buscar
      toBlock = fromBlock - 1;
    }
    return null;
  }

  // Exposto publicamente — o SmartAccountActivityScanner (aba Wallet) precisa
  // do bloco mais recente como `toBlock` do scan de histórico completo.
  Future<int?> getLatestBlockNumber() async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_blockNumber',
        'params': [],
        'id': 1,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('error')) return null;
      return int.parse((json['result'] as String).substring(2), radix: 16);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<List<dynamic>?> _fetchIdentityCreatedLogs({
    required String eventTopic,
    required String idTopic,
    required int fromBlock,
    required int toBlock,
  }) async {
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
            'fromBlock': '0x${fromBlock.toRadixString(16)}',
            'toBlock': '0x${toBlock.toRadixString(16)}',
          }
        ],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) return null;
      return json['result'] as List<dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  String _decodeUsernameFromLog(Map<String, dynamic> log) {
    // ABI-decode the non-indexed `string username` from log.data.
    // Layout: [0-31] offset=0x20 | [32-63] length N | [64-64+N] UTF-8 bytes
    final dataHex = (log['data'] as String).substring(2);
    final length = int.parse(dataHex.substring(64, 128), radix: 16);
    final strHex = dataHex.substring(128, 128 + length * 2);
    final strBytes = Uint8List.fromList(
      List.generate(strHex.length ~/ 2,
          (i) => int.parse(strHex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
    return utf8.decode(strBytes);
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
  // Decodificação manual, não via fn.decodeReturnValues — o decoder de tuplas
  // do web3dart não lida direito com uma struct que tem um campo dinâmico
  // (`string username`) entre campos fixos: o `exists` (bool) vinha sempre
  // null (achado real, Sessão 70). Layout ABI conhecido pra essa struct:
  // [outerOffset(32B)] [id(32B)] [stringOffset(32B)] [controller(32B)]
  // [exists(32B)] [stringLen(32B)] [stringBytes...] — só os 4 primeiros
  // campos (tudo antes do texto dinâmico) importam aqui.
  Future<IdentityInfo?> getIdentityByUsername(String username) async {
    // Calldata montado à mão — não usa fn.encodeCall/_identityContract.function
    // de propósito. O bug do web3dart não estava só no decode (débito #32):
    // mesmo evitando decodeReturnValues, a construção da chamada via
    // ContractFunction (que também enxerga a struct de saída com o campo
    // dinâmico no meio) reproduzia o mesmo erro "null is not a subtype of
    // bool" antes de qualquer resposta da rede chegar (Sessão 70). Selector
    // e encoding manuais eliminam qualquer contato com esse caminho do
    // web3dart pra esta chamada específica.
    final selector =
        keccak256(Uint8List.fromList(utf8.encode('getIdentity(string)')))
            .sublist(0, 4);
    final usernameBytes = Uint8List.fromList(utf8.encode(username));
    final paddedLength = ((usernameBytes.length + 31) ~/ 32) * 32;
    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256Bytes(32)) // offset do parâmetro dinâmico
      ..add(_uint256Bytes(usernameBytes.length)) // tamanho da string
      ..add(usernameBytes)
      ..add(Uint8List(paddedLength - usernameBytes.length)); // padding pra 32 bytes

    final resultHex = await _ethCallRawHex(
        _identityRegistryAddress, callData.toBytes());

    final id = BigInt.parse(resultHex.substring(64, 128), radix: 16);
    final controllerHex = resultHex.substring(216, 256);
    final exists = BigInt.parse(resultHex.substring(256, 320), radix: 16) != BigInt.zero;
    if (!exists) return null;

    return IdentityInfo(
      id: id,
      controller: EthereumAddress.fromHex('0x$controllerHex'),
    );
  }

  Uint8List _uint256Bytes(int value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList(List.generate(
        32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
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

  // Saldo nativo (ETH) da smart account, em wei. Espelha o que o dashboard
  // do Desktop já mostra (`useBalance` do wagmi, 14.10) — aqui via
  // eth_getBalance cru, mesmo padrão de JSON-RPC manual usado no resto deste
  // service (sem depender de Web3Client do web3dart).
  Future<BigInt> getBalance(EthereumAddress address) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_getBalance',
        'params': [address.hex, 'latest'],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception('RPC error: ${json['error']}');
      }

      return BigInt.parse((json['result'] as String).substring(2), radix: 16);
    } finally {
      client.close();
    }
  }

  // eth_getLogs genérico — generaliza _fetchIdentityCreatedLogs (endereço
  // parametrizado em vez de hardcoded pro IdentityRegistry). Usado pelo
  // SmartAccountActivityScanner (aba Wallet) pra escanear os 5 tipos de
  // evento de atividade. Diferente de _fetchIdentityCreatedLogs (que engole
  // erro e tenta o chunk anterior — estratégia de busca bounded), este método
  // **lança exceção** em erro: o scanner precisa que falha de rede vire um
  // erro real na UI, não um resultado silenciosamente incompleto.
  Future<List<Map<String, dynamic>>> getLogs({
    required String address,
    required List<String> topics,
    required int fromBlock,
    required int toBlock,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_getLogs',
        'params': [
          {
            'address': address,
            'topics': topics,
            'fromBlock': '0x${fromBlock.toRadixString(16)}',
            'toBlock': '0x${toBlock.toRadixString(16)}',
          }
        ],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception('RPC error: ${json['error']}');
      }

      return (json['result'] as List).cast<Map<String, dynamic>>();
    } finally {
      client.close();
    }
  }

  // eth_getTransactionReceipt — novo nesta base de código. Usado pelo
  // SmartAccountActivityScanner pra calcular o custo (gasUsed *
  // effectiveGasPrice) da tx que emitiu cada evento de atividade.
  Future<TxReceiptInfo> getTransactionReceipt(String txHash) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_getTransactionReceipt',
        'params': [txHash],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error') || json['result'] == null) {
        throw Exception('RPC error fetching receipt for $txHash: ${json['error']}');
      }

      final result = json['result'] as Map<String, dynamic>;
      return TxReceiptInfo(
        gasUsed: BigInt.parse((result['gasUsed'] as String).substring(2), radix: 16),
        effectiveGasPrice:
            BigInt.parse((result['effectiveGasPrice'] as String).substring(2), radix: 16),
      );
    } finally {
      client.close();
    }
  }

  // eth_getBlockByNumber (sem transações completas — segundo parâmetro
  // `false`) — novo nesta base de código. Usado pelo SmartAccountActivityScanner
  // pra resolver o timestamp de cada evento de atividade a partir do bloco.
  Future<int> getBlockTimestamp(int blockNumber) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'eth_getBlockByNumber',
        'params': ['0x${blockNumber.toRadixString(16)}', false],
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error') || json['result'] == null) {
        throw Exception('RPC error fetching block $blockNumber: ${json['error']}');
      }

      final result = json['result'] as Map<String, dynamic>;
      return int.parse((result['timestamp'] as String).substring(2), radix: 16);
    } finally {
      client.close();
    }
  }
}

// Custo de uma transação (gasUsed * effectiveGasPrice) — usado pelo
// SmartAccountActivityScanner pra calcular o `costWei` de cada atividade.
class TxReceiptInfo {
  final BigInt gasUsed;
  final BigInt effectiveGasPrice;

  const TxReceiptInfo({required this.gasUsed, required this.effectiveGasPrice});
}

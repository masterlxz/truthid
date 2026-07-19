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
  // Opcionais, default vazio — não populados pelos call sites antigos deste
  // tipo (só `getDevice()` os preenche hoje). Adicionados pra dar suporte à
  // tela de "Permissões por device" (mirror de `DeviceInfo` no Desktop,
  // `desktop/src/types.ts:1-8`, que já tem os dois).
  final String pubKey;
  final String label;

  const DeviceInfo({
    required this.identityId,
    required this.revoked,
    required this.exists,
    this.pubKey = '',
    this.label = '',
  });
}

// Dados de uma identidade retornados pelo IdentityRegistry — usado pela 14.9.5
// pra resolver o endereço da smart account (controller) que assina a UserOp.
class IdentityInfo {
  final BigInt id;
  final EthereumAddress controller;

  const IdentityInfo({required this.id, required this.controller});
}

// Referência atual do vault publicado, lida do VaultRegistry — usado pelo
// VaultSyncService (13.8) pra saber onde baixar o blob cifrado e como
// verificar sua integridade antes de decifrar.
class VaultRef {
  final String cid;
  final String contentHashHex; // "0x"-prefixed, keccak256 do blob cifrado
  final DateTime updatedAt;
  final int version;

  const VaultRef({
    required this.cid,
    required this.contentHashHex,
    required this.updatedAt,
    required this.version,
  });
}

class BlockchainService {
  // Endereços atualizados no redeploy de 2026-07-04 (corrige bug do
  // getAddress de 1 argumento no IdentityRegistry — ver PROJECT_STATE.md).
  //
  // RPCs públicos de Base Mainnet, na ordem em que são tentados — mesma lista
  // já usada no fallback do Desktop (ver desktop/src/config/wagmi.ts). Antes
  // o mobile dependia de um único RPC hardcoded sem fallback: um rate limit
  // dele (erro -32016 "over rate limit", visto ao vivo na Sessão 92) derrubava
  // toda leitura on-chain do app.
  static const _rpcUrls = [
    'https://mainnet.base.org',
    'https://base-rpc.publicnode.com',
    'https://base.drpc.org',
  ];
  static const _rpcTimeout = Duration(seconds: 10);

  // Sessão 122: um scan de histórico completo da aba Wallet dispara volume
  // suficiente de eth_getLogs pra estourar rate limit nos 3 RPCs públicos ao
  // mesmo tempo (não é falha isolada de 1 deles — esse caso já era coberto
  // pelo fallback acima desde o débito #53). Percorrer a lista de novo, com
  // um breve intervalo, dá tempo do rate limit (normalmente janela de
  // segundos num RPC público) esvaziar antes de desistir de vez.
  static const _rpcRetryRounds = 3;
  static const _rpcRetryBackoff = Duration(milliseconds: 500);
  static const _sessionRegistryAddress =
      '0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df';
  static const _deviceRegistryAddress =
      '0x4Fd53d70553df00D42c015EB35E2626cB80b1614';
  static const _identityRegistryAddress =
      '0xC11426fd1cB103bC56dD3263325b34f2AcEe9903';
  // Primeiro deploy do VaultRegistry, Sessão 88 — mesmo endereço Mainnet já
  // usado em desktop/src/config/contracts.ts.
  static const _vaultRegistryAddress =
      '0x602Fa39611960e5ef17D95a5d7b16816eE0ff734';

  // Exposto publicamente — a 14.9.5 (SessionCreator) precisa deste endereço
  // como `dest` da chamada `TruthIDAccount.execute`.
  static const sessionRegistryAddress = _sessionRegistryAddress;

  // Exposto publicamente — SessionCreator.updateVault (Sessão 97) precisa
  // deste endereço como `dest` da chamada `TruthIDAccount.execute`.
  static const vaultRegistryAddress = _vaultRegistryAddress;

  // Exposto publicamente — o SmartAccountActivityScanner (aba Wallet) precisa
  // deste endereço pra escanear os eventos DeviceRegistered/DeviceRevoked.
  static const deviceRegistryAddress = _deviceRegistryAddress;

  // Blocos de deploy na Base Mainnet (redeploy da Sessão 88, débito #42) —
  // mesmos valores já usados no Desktop (desktop/src/config/contracts.ts),
  // confirmados nos artefatos de broadcast do Foundry. Ponto de partida do
  // scan de histórico completo da aba Wallet.
  static const deviceRegistryDeployBlock = 48294070;
  static const sessionRegistryDeployBlock = 48294090;
  // IdentityRegistry é deployado antes dos outros dois no mesmo script —
  // ponto de partida do scan pra frente em getUsernameForIdentity.
  static const identityRegistryDeployBlock = 48294068;

  // Única rede configurada hoje é Base Mainnet (ver _rpcUrls acima) — por
  // isso um único chainId fixo, em vez de um mapa rede→chainId que nada usaria.
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
    final result = await _rpcCall('eth_call', [
      {'to': contractAddress, 'data': callDataHex},
      'latest',
    ]);
    return (result as String).substring(2);
  }

  // Faz uma chamada JSON-RPC tentando cada URL de _rpcUrls em ordem — mesmo
  // esquema de fallback do IpfsGatewayClient (ver ipfs_gateway_client.dart):
  // a primeira resposta bem-sucedida vence, qualquer falha (rede, timeout ou
  // 'error' no corpo) passa pro próximo RPC da lista.
  Future<dynamic> _rpcCall(String method, List<dynamic> params) async {
    final errors = <String>[];
    for (var round = 0; round < _rpcRetryRounds; round++) {
      for (final url in _rpcUrls) {
        try {
          return await _rpcCallOnce(url, method, params).timeout(_rpcTimeout);
        } catch (e) {
          errors.add('$url: $e');
        }
      }
      if (round < _rpcRetryRounds - 1) {
        await Future.delayed(_rpcRetryBackoff * (round + 1));
      }
    }
    throw Exception('Todos os RPCs falharam para $method: ${errors.join('; ')}');
  }

  Future<dynamic> _rpcCallOnce(
      String url, String method, List<dynamic> params) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception('RPC error: ${json['error']}');
      }

      return json['result'];
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

  // Resolve o @username da identidade via eth_getLogs no evento IdentityCreated.
  // O contrato não tem um getter id→username, então a única fonte é o log.
  // Pagina PRA FRENTE a partir de identityRegistryDeployBlock (nunca antes
  // disso) até "latest" — cobre qualquer identidade, não só as recentes.
  //
  // Achado real (Sessão 134): a versão anterior paginava pra trás a partir
  // de "latest" com uma janela fixa de 50 faixas (~100k blocos) — suficiente
  // só pra identidade pareada há pouco tempo (o caso de uso original,
  // DevicesScreen logo após descobrir um pareamento novo). Meses depois, com
  // a chain ~550k blocos à frente do deploy, a identidade #1 (criada junto
  // do deploy) ficou permanentemente fora dessa janela — username nunca mais
  // resolvia, travando saldo/atividade da aba Wallet pra sempre (nenhum
  // retry corrigia, o scan sempre parava na mesma janela recente vazia).
  // Escanear pra frente a partir do deploy garante achar qualquer identidade
  // mais cedo ou mais tarde — pra uma identidade antiga, a resposta vem já
  // no primeiro chunk (perto do próprio deploy); pra uma criada há pouco, o
  // scan varre até o fim antes de achar, mais chunks mas ainda correto.
  // Retorna null se não encontrar (identidade não existe) ou se o RPC falhar.
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

    var fromBlock = identityRegistryDeployBlock;
    while (fromBlock <= latestBlock) {
      final toBlock = fromBlock + _maxLogRangeBlocks - 1 < latestBlock
          ? fromBlock + _maxLogRangeBlocks - 1
          : latestBlock;

      final logs = await _fetchIdentityCreatedLogs(
        eventTopic: eventTopic,
        idTopic: idTopic,
        fromBlock: fromBlock,
        toBlock: toBlock,
      );
      if (logs != null && logs.isNotEmpty) {
        return _decodeUsernameFromLog(logs.first as Map<String, dynamic>);
      }

      fromBlock = toBlock + 1;
    }
    return null;
  }

  // Exposto publicamente — o SmartAccountActivityScanner (aba Wallet) precisa
  // do bloco mais recente como `toBlock` do scan de histórico completo.
  Future<int?> getLatestBlockNumber() async {
    try {
      final result = await _rpcCall('eth_blockNumber', []);
      return int.parse((result as String).substring(2), radix: 16);
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> _fetchIdentityCreatedLogs({
    required String eventTopic,
    required String idTopic,
    required int fromBlock,
    required int toBlock,
  }) async {
    try {
      final result = await _rpcCall('eth_getLogs', [
        {
          'address': _identityRegistryAddress,
          'topics': [eventTopic, idTopic],
          'fromBlock': '0x${fromBlock.toRadixString(16)}',
          'toBlock': '0x${toBlock.toRadixString(16)}',
        }
      ]);
      return result as List<dynamic>;
    } catch (_) {
      return null;
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
        pubKey: address,
        label: tuple[2] as String,
      );
    } catch (_) {
      return null;
    }
  }

  // Lista os pubkeys de todos os devices já registrados pra uma identidade
  // (ativos ou revogados — quem chama filtra). Usado pela tela de
  // "Permissões por device" pra montar a lista completa antes de cruzar com
  // `VaultRepository.listDevicePermissions()`. Mirror do par
  // `getDevicesByIdentity`+`getDevice` que o Desktop já usa em
  // `VaultManagement.tsx` (`useReadContract`/`useReadContracts`).
  Future<List<String>> getDevicesForIdentity(BigInt identityId) async {
    final fn = _deviceContract.function('getDevicesByIdentity');
    final result = await _ethCall(_deviceRegistryAddress, fn, [identityId]);
    final addresses = (result[0] as List<dynamic>).cast<EthereumAddress>();
    return addresses.map((a) => a.hex).toList();
  }

  Future<Uint8List?> getDeviceVaultKey(String address) async {
    try {
      final fn = _deviceContract.function('deviceVaultKeys');
      final result = await _ethCall(
        _deviceRegistryAddress,
        fn,
        [EthereumAddress.fromHex(address)],
      );
      final bytes = result[0] as List<int>;
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
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

  // Variante de _uint256Bytes pra identityId, que é BigInt no resto deste
  // arquivo (ver getSessionsForIdentity) — _uint256Bytes só aceita int.
  Uint8List _uint256BytesFromBigInt(BigInt value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList(List.generate(
        32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
  }

  // Retorna true se a identidade já tem um vault publicado. Seguro chamar
  // especulativamente (ao contrário de getVault, que reverte se não existir).
  Future<bool> hasVault(BigInt identityId) async {
    final selector =
        keccak256(Uint8List.fromList(utf8.encode('hasVault(uint256)')))
            .sublist(0, 4);
    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256BytesFromBigInt(identityId));

    final resultHex =
        await _ethCallRawHex(_vaultRegistryAddress, callData.toBytes());
    return BigInt.parse(resultHex.substring(0, 64), radix: 16) != BigInt.zero;
  }

  // Retorna a referência atual do vault publicado (cid/contentHash/versão).
  // getVault REVERTE (VaultNotFound) se não houver vault — chame hasVault
  // antes; uma exceção aqui é sempre erro real (rede ou revert), nunca um
  // jeito de descobrir "não existe". Decodificação manual pelo mesmo motivo
  // de getIdentityByUsername: VaultRef tem um campo dinâmico (`string cid`)
  // na struct de retorno — o decoder de tuplas do web3dart não lida direito
  // com isso (débito #32). Layout ABI conhecido pra essa struct:
  // [outerOffset(32B)] [cidOffset(32B)] [contentHash(32B)] [updatedAt(32B)]
  // [version(32B)] [exists(32B)] [cidLen(32B)] [cidBytes...] — exists não
  // precisa ser decodificado: a chamada já teria revertido se fosse false.
  Future<VaultRef> getVault(BigInt identityId) async {
    final selector =
        keccak256(Uint8List.fromList(utf8.encode('getVault(uint256)')))
            .sublist(0, 4);
    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256BytesFromBigInt(identityId));

    final resultHex =
        await _ethCallRawHex(_vaultRegistryAddress, callData.toBytes());

    final contentHash = resultHex.substring(128, 192);
    final updatedAt = BigInt.parse(resultHex.substring(192, 256), radix: 16);
    final version = BigInt.parse(resultHex.substring(256, 320), radix: 16);
    final cidLength = int.parse(resultHex.substring(384, 448), radix: 16);
    final cidHex = resultHex.substring(448, 448 + cidLength * 2);
    final cidBytes = Uint8List.fromList(List.generate(cidHex.length ~/ 2,
        (i) => int.parse(cidHex.substring(i * 2, i * 2 + 2), radix: 16)));

    return VaultRef(
      cid: utf8.decode(cidBytes),
      contentHashHex: '0x$contentHash',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt() * 1000),
      version: version.toInt(),
    );
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
    final result = await _rpcCall('eth_getBalance', [address.hex, 'latest']);
    return BigInt.parse((result as String).substring(2), radix: 16);
  }

  // eth_getLogs genérico — generaliza _fetchIdentityCreatedLogs (endereço
  // parametrizado em vez de hardcoded pro IdentityRegistry). Usado pelo
  // SmartAccountActivityScanner (aba Wallet) pra escanear os 5 tipos de
  // evento de atividade numa chamada só por chunk (Sessão 122: `addresses` e
  // `topics[0]` aceitam lista — o nó já faz o OR dentro da posição — em vez
  // de 5 chamadas paralelas, uma por endereço/topic0). Diferente de
  // _fetchIdentityCreatedLogs (que engole erro e tenta o chunk anterior —
  // estratégia de busca bounded), este método **lança exceção** em erro: o
  // scanner precisa que falha de rede vire um erro real na UI, não um
  // resultado silenciosamente incompleto.
  Future<List<Map<String, dynamic>>> getLogs({
    required List<String> addresses,
    required List<dynamic> topics,
    required int fromBlock,
    required int toBlock,
  }) async {
    final result = await _rpcCall('eth_getLogs', [
      {
        'address': addresses.length == 1 ? addresses.first : addresses,
        'topics': topics,
        'fromBlock': '0x${fromBlock.toRadixString(16)}',
        'toBlock': '0x${toBlock.toRadixString(16)}',
      }
    ]);
    return (result as List).cast<Map<String, dynamic>>();
  }

  // eth_getTransactionReceipt — novo nesta base de código. Usado pelo
  // SmartAccountActivityScanner pra calcular o custo (gasUsed *
  // effectiveGasPrice) da tx que emitiu cada evento de atividade.
  Future<TxReceiptInfo> getTransactionReceipt(String txHash) async {
    final result = await _rpcCall('eth_getTransactionReceipt', [txHash]);
    if (result == null) {
      throw Exception('RPC error fetching receipt for $txHash: result null');
    }
    final map = result as Map<String, dynamic>;
    return TxReceiptInfo(
      gasUsed: BigInt.parse((map['gasUsed'] as String).substring(2), radix: 16),
      effectiveGasPrice:
          BigInt.parse((map['effectiveGasPrice'] as String).substring(2), radix: 16),
    );
  }

  // eth_getBlockByNumber (sem transações completas — segundo parâmetro
  // `false`) — novo nesta base de código. Usado pelo SmartAccountActivityScanner
  // pra resolver o timestamp de cada evento de atividade a partir do bloco.
  Future<int> getBlockTimestamp(int blockNumber) async {
    final result = await _rpcCall(
        'eth_getBlockByNumber', ['0x${blockNumber.toRadixString(16)}', false]);
    if (result == null) {
      throw Exception('RPC error fetching block $blockNumber: result null');
    }
    final map = result as Map<String, dynamic>;
    return int.parse((map['timestamp'] as String).substring(2), radix: 16);
  }
}

// Custo de uma transação (gasUsed * effectiveGasPrice) — usado pelo
// SmartAccountActivityScanner pra calcular o `costWei` de cada atividade.
class TxReceiptInfo {
  final BigInt gasUsed;
  final BigInt effectiveGasPrice;

  const TxReceiptInfo({required this.gasUsed, required this.effectiveGasPrice});
}

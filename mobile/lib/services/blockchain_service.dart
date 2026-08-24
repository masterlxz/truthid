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
  // getAddress de 1 argumento no IdentityRegistry — ver project/INDEX.md).
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
      '0x8C65527eDA3ce7754Bf87B34aC4ec8ce74D647e2';
  static const _deviceRegistryAddress =
      '0x937702CBABDab0EEBD1A29f0a7A658FeF4582543';
  static const _identityRegistryAddress =
      '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962';
  // Mesmo endereço já usado em desktop/src/config/truthidAccount.ts
  // (TRUTHID_ACCOUNT_FACTORY_ADDRESS). Único ponto de verdade pro endereço
  // previsto de uma smart account é a view `getAddress` on-chain (ver
  // predictSmartAccountAddress abaixo) — nunca replicar CREATE2 localmente,
  // foi exatamente isso que causou o bug real do P66 no Desktop.
  static const _truthidAccountFactoryAddress =
      '0xc2C86cB7d8694EcA8BaAdD95B14842E8643aB262';
  // Redeploy em cascata (débito #52) — mesmo endereço Mainnet já usado em
  // desktop/src/config/contracts.ts.
  static const _vaultRegistryAddress =
      '0x07449b0c8dAE1252f59A5C0992D1413113a849B4';
  static const _recoveryManagerAddress =
      '0x42Ca394c23aB027e877B9900B384f59E2Af23470';

  // Exposto publicamente — a 14.9.5 (SessionCreator) precisa deste endereço
  // como `dest` da chamada `TruthIDAccount.execute`.
  static const sessionRegistryAddress = _sessionRegistryAddress;

  // Exposto publicamente — SessionCreator.updateVault (Sessão 97) precisa
  // deste endereço como `dest` da chamada `TruthIDAccount.execute`.
  static const vaultRegistryAddress = _vaultRegistryAddress;

  // Exposto publicamente — o SmartAccountActivityScanner (aba Wallet) precisa
  // deste endereço pra escanear os eventos DeviceRegistered/DeviceRevoked.
  static const deviceRegistryAddress = _deviceRegistryAddress;

  // Exposto publicamente — buildIdentityConsentHash (P68, fatia 1) precisa
  // deste endereço fora deste arquivo, pro mesmo hash que
  // IdentityRegistry.sol verifica via ecrecover.
  static const identityRegistryAddress = _identityRegistryAddress;

  // Exposto publicamente — CreateIdentityScreen (P68, fatia 1) precisa deste
  // endereço como `to` da transação createAccount.
  static const truthidAccountFactoryAddress = _truthidAccountFactoryAddress;

  // Exposto publicamente — ConfigureGuardiansScreen (P68, fatia 2) precisa
  // deste endereço como `dest` da chamada TruthIDAccount.execute.
  static const recoveryManagerAddress = _recoveryManagerAddress;

  // Blocos de deploy na Base Mainnet (redeploy em cascata, débito #52) —
  // mesmos valores já usados no Desktop (desktop/src/config/contracts.ts),
  // confirmados nos artefatos de broadcast do Foundry. Ponto de partida do
  // scan de histórico completo da aba Wallet.
  static const deviceRegistryDeployBlock = 49935103;
  static const sessionRegistryDeployBlock = 49935140;
  // IdentityRegistry é deployado antes dos outros dois no mesmo script —
  // ponto de partida do scan pra frente em getUsernameForIdentity.
  static const identityRegistryDeployBlock = 49935101;

  // Única rede configurada hoje é Base Mainnet (ver _rpcUrls acima) — por
  // isso um único chainId fixo, em vez de um mapa rede→chainId que nada usaria.
  static final chainId = BigInt.from(8453);

  // Ligada — o SessionRegistry novo (redeploy em cascata, débito #52) já
  // verifica keccak256(chainId, address(this), hash) na assinatura de
  // sessão (fix C4). Ver P26 em PENDING.md.
  static const sessionDomainSeparationEnabled = true;

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

  static final _recoveryContract = DeployedContract(
    ContractAbi.fromJson(recoveryManagerAbi, 'RecoveryManager'),
    EthereumAddress.fromHex(_recoveryManagerAddress),
  );

  static final _identityContract = DeployedContract(
    ContractAbi.fromJson(identityRegistryAbi, 'IdentityRegistry'),
    EthereumAddress.fromHex(_identityRegistryAddress),
  );

  static final _factoryContract = DeployedContract(
    ContractAbi.fromJson(truthidAccountFactoryAbi, 'TruthIDAccountFactory'),
    EthereumAddress.fromHex(_truthidAccountFactoryAddress),
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

  // Quantas faixas de _maxLogRangeBlocks a fase 1 (rápida) cobre a partir do
  // tip — mesma janela (~100k blocos) que a versão original (Sessão 134)
  // usava como única estratégia. Cobre o caso comum (identidade pareada há
  // pouco tempo) em 1-2 chunks.
  static const _recentLookbackChunks = 50;

  // Resolve o @username da identidade via eth_getLogs no evento IdentityCreated.
  // O contrato não tem um getter id→username, então a única fonte é o log.
  //
  // Duas fases, achado real da Sessão 135 (revisão do fix da Sessão 134):
  // fase 1 pagina PRA TRÁS a partir de "latest", limitada a
  // _recentLookbackChunks — cobre rápido o caso comum (DevicesScreen logo
  // após descobrir um pareamento novo, identidade criada perto do tip).
  // Fase 2, só se a 1 não achar, pagina PRA FRENTE a partir de
  // identityRegistryDeployBlock até onde a fase 1 já começou (sem repetir
  // blocos) — sem teto, mas só roda pro caso raro de identidade antiga
  // (ex: identidade #1, criada junto do deploy, é o motivo desta fase
  // existir: só scan pra trás com janela fixa a deixava fora de alcance pra
  // sempre, travando saldo/atividade da aba Wallet). A fase 1 sozinha (como
  // na Sessão 134 original) resolvia isso trocando pra frente incondicional,
  // mas aí uma identidade recém-criada passava a precisar de centenas de
  // chunks sequenciais pra ser achada — regressão real no caso comum pra
  // corrigir o raro. As duas fases juntas cobrem os dois sem penalizar um
  // pelo outro. Retorna null se não encontrar (identidade não existe) ou se
  // o RPC falhar.
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

    final recentWindowStartUnclamped =
        latestBlock - _recentLookbackChunks * _maxLogRangeBlocks + 1;
    final recentWindowStart = recentWindowStartUnclamped > identityRegistryDeployBlock
        ? recentWindowStartUnclamped
        : identityRegistryDeployBlock;

    // Fase 1 — pra trás, limitada, cobre [recentWindowStart, latestBlock].
    var toBlock = latestBlock;
    while (toBlock >= recentWindowStart) {
      final fromBlock = toBlock - _maxLogRangeBlocks + 1 > recentWindowStart
          ? toBlock - _maxLogRangeBlocks + 1
          : recentWindowStart;

      final logs = await _fetchIdentityCreatedLogs(
        eventTopic: eventTopic,
        idTopic: idTopic,
        fromBlock: fromBlock,
        toBlock: toBlock,
      );
      if (logs != null && logs.isNotEmpty) {
        return _decodeUsernameFromLog(logs.first as Map<String, dynamic>);
      }

      toBlock = fromBlock - 1;
    }

    // Fase 2 — pra frente, sem teto, cobre [identityRegistryDeployBlock,
    // recentWindowStart - 1] (o que a fase 1 ainda não cobriu). Só executa
    // se recentWindowStart > identityRegistryDeployBlock — perto do deploy,
    // a fase 1 já cobre a chain inteira e este loop não roda.
    var fromBlock = identityRegistryDeployBlock;
    while (fromBlock < recentWindowStart) {
      final chunkEnd = fromBlock + _maxLogRangeBlocks - 1 < recentWindowStart - 1
          ? fromBlock + _maxLogRangeBlocks - 1
          : recentWindowStart - 1;

      final logs = await _fetchIdentityCreatedLogs(
        eventTopic: eventTopic,
        idTopic: idTopic,
        fromBlock: fromBlock,
        toBlock: chunkEnd,
      );
      if (logs != null && logs.isNotEmpty) {
        return _decodeUsernameFromLog(logs.first as Map<String, dynamic>);
      }

      fromBlock = chunkEnd + 1;
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

  // _rpcCall já tenta 3 rounds × 3 URLs (9 tentativas) antes de desistir —
  // mas o loop de getUsernameForIdentity trata "chunk falhou" e "chunk sem
  // logs" como a mesma coisa (null), então uma falha aqui pula o chunk
  // silenciosamente em vez de tentar de novo. Achado real (ultrareview): com
  // a fase 2 (sem teto) podendo varrer centenas de chunks pra identidades
  // antigas, a chance acumulada de UM chunk específico (o que tem o log de
  // verdade) falhar por acaso cresce — uma 2ª rodada completa aqui reduz
  // bastante essa chance, sem mudar o contrato de retorno (String?) que
  // todo mundo já espera.
  Future<List<dynamic>?> _fetchIdentityCreatedLogs({
    required String eventTopic,
    required String idTopic,
    required int fromBlock,
    required int toBlock,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
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
        if (attempt == 0) await Future.delayed(_rpcRetryBackoff);
      }
    }
    return null;
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

  // Confirma se um @username já está em uso — checagem de leitura antes de
  // gastar gas com createIdentity (P68, fatia 1, mesmo guard que
  // CreateIdentity.tsx já faz no Desktop via useReadContract).
  Future<bool> isUsernameTaken(String username) async {
    final fn = _identityContract.function('isUsernameTaken');
    final result = await _ethCall(_identityRegistryAddress, fn, [username]);
    return result[0] as bool;
  }

  // Resolve o @username já registrado pra um controller (endereço da smart
  // account), se houver — mesma checagem que CreateIdentity.tsx faz no
  // Desktop pra evitar criar uma 2ª identidade pra uma wallet que já tem uma.
  // Retorna string vazia se não achar (fonte de verdade: isUsernameTaken
  // acima é quem decide "está em uso", aqui só resolvemos o nome quando já
  // se sabe que existe).
  Future<String> getUsernameByController(EthereumAddress controller) async {
    final fn = _identityContract.function('getUsernameByController');
    final result = await _ethCall(_identityRegistryAddress, fn, [controller]);
    return result[0] as String;
  }

  // Endereço (20 bytes) alinhado à direita num slot de 32 bytes — mesma
  // convenção ABI que _uint256Bytes já usa, só com zeros à esquerda em vez
  // de um valor numérico. Usado pelos calldata builders abaixo.
  Uint8List _addressBytes(EthereumAddress address) {
    final raw = address.addressBytes;
    return Uint8List.fromList([...Uint8List(32 - raw.length), ...raw]);
  }

  // Calldata de IdentityRegistry.createIdentity(username, controller, v, r, s)
  // — codificado à mão, mesmo motivo de getIdentityByUsername/hasVault/getVault
  // (débito #32: o encoder de ContractFunction do web3dart não é confiável
  // pra esta base de código quando há um tipo dinâmico envolvido — aqui é só
  // um parâmetro dinâmico (username) e ele é o primeiro, então tecnicamente
  // seria um caso mais simples, mas hand-rolling elimina qualquer dúvida
  // sobre o comportamento do encoder pra `uint8`/`bytes32`, nunca exercitados
  // em outro lugar deste arquivo). `v`/`r`/`s` vêm de
  // utils/ecdsa_signature.dart (P68, fatia 1).
  Uint8List buildCreateIdentityCalldata({
    required String username,
    required EthereumAddress controller,
    required int v,
    required Uint8List r,
    required Uint8List s,
  }) {
    final selector = keccak256(Uint8List.fromList(
            utf8.encode('createIdentity(string,address,uint8,bytes32,bytes32)')))
        .sublist(0, 4);
    final usernameBytes = Uint8List.fromList(utf8.encode(username));
    final paddedUsernameLen = ((usernameBytes.length + 31) ~/ 32) * 32;

    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256Bytes(160)) // offset do único param dinâmico: 5*32
      ..add(_addressBytes(controller))
      ..add(_uint256Bytes(v))
      ..add(r)
      ..add(s)
      ..add(_uint256Bytes(usernameBytes.length))
      ..add(usernameBytes)
      ..add(Uint8List(paddedUsernameLen - usernameBytes.length));

    return callData.toBytes();
  }

  // Calldata de TruthIDAccountFactory.createAccount(owner_, index) — sem
  // parâmetro dinâmico nenhum, o mais simples dos dois.
  Uint8List buildCreateAccountCalldata(EthereumAddress owner) {
    final selector = keccak256(
            Uint8List.fromList(utf8.encode('createAccount(address,uint256)')))
        .sublist(0, 4);
    final callData = BytesBuilder()
      ..add(selector)
      ..add(_addressBytes(owner))
      ..add(_uint256Bytes(0)); // index, sempre 0 nesta app
    return callData.toBytes();
  }

  // ── Parear device + configurar guardians (P68, fatia 2) ───────────────────
  //
  // Toda escrita abaixo é roteada pela smart account (TruthIDAccount.execute
  // /executeBatch), nunca chamando DeviceRegistry/RecoveryManager direto —
  // `msg.sender` visto por esses contratos precisa ser o controller (a smart
  // account), não a wallet externa que assina via WalletConnect. Confirmado
  // lendo DeviceRegistry.sol (comentário do commitDevice) e
  // GuardianManagement.tsx (handleConfigure) no Desktop, que já faz exatamente
  // isso — `sendConfig({ functionName: "execute", args: [dest, value, func] })`.

  /// commitment = keccak256(abi.encodePacked(devicePubKey, salt, smartAccount))
  /// — abi.encodePacked de (address,bytes32,address) é concatenação crua sem
  /// padding (20+32+20 = 72 bytes), diferente do abi.encode usado pelos
  /// outros builders deste arquivo.
  Uint8List buildDeviceCommitment({
    required EthereumAddress devicePubKey,
    required Uint8List salt,
    required EthereumAddress smartAccount,
  }) {
    final packed = Uint8List.fromList([
      ...devicePubKey.addressBytes,
      ...salt,
      ...smartAccount.addressBytes,
    ]);
    return keccak256(packed);
  }

  // Calldata de DeviceRegistry.commitDevice(bytes32) — sem parâmetro
  // dinâmico.
  Uint8List buildCommitDeviceCalldata(Uint8List commitment) {
    final selector = keccak256(
            Uint8List.fromList(utf8.encode('commitDevice(bytes32)')))
        .sublist(0, 4);
    return (BytesBuilder()
          ..add(selector)
          ..add(commitment))
        .toBytes();
  }

  // Calldata de DeviceRegistry.registerDevice(address,string,bytes32,bytes)
  // — os slots do cabeçalho seguem a ORDEM DE DECLARAÇÃO dos parâmetros, não
  // "estáticos primeiro": devicePubKey (estático, inline), offset_label
  // (string é o 2º parâmetro, dinâmico), salt (bytes32 é ESTÁTICO — tamanho
  // fixo, vai inline mesmo sendo o 3º parâmetro, não no bloco de dados
  // dinâmicos), offset_encryptedVaultKey (4º parâmetro, dinâmico). Achado
  // real (P68, fatia 2): a 1ª versão agrupava os 2 estáticos primeiro
  // (devicePubKey, salt) e só depois os 2 offsets — divergia do vetor viem
  // real porque a ABI exige a ordem de declaração dos parâmetros no
  // cabeçalho, nunca reagrupada por "estático vs. dinâmico".
  Uint8List buildRegisterDeviceCalldata({
    required EthereumAddress devicePubKey,
    required String label,
    required Uint8List salt,
    required Uint8List encryptedVaultKey,
  }) {
    final selector = keccak256(Uint8List.fromList(
            utf8.encode('registerDevice(address,string,bytes32,bytes)')))
        .sublist(0, 4);

    final labelBytes = Uint8List.fromList(utf8.encode(label));
    final paddedLabelLen = ((labelBytes.length + 31) ~/ 32) * 32;
    final paddedKeyLen = ((encryptedVaultKey.length + 31) ~/ 32) * 32;

    final labelOffset = 128; // 4 slots de cabeçalho * 32
    final labelBlockLen = 32 + paddedLabelLen; // slot de tamanho + dados
    final keyOffset = labelOffset + labelBlockLen;

    final callData = BytesBuilder()
      ..add(selector)
      ..add(_addressBytes(devicePubKey))
      ..add(_uint256Bytes(labelOffset))
      ..add(salt)
      ..add(_uint256Bytes(keyOffset))
      ..add(_uint256Bytes(labelBytes.length))
      ..add(labelBytes)
      ..add(Uint8List(paddedLabelLen - labelBytes.length))
      ..add(_uint256Bytes(encryptedVaultKey.length))
      ..add(encryptedVaultKey)
      ..add(Uint8List(paddedKeyLen - encryptedVaultKey.length));

    return callData.toBytes();
  }

  // Calldata de TruthIDAccount.addDevice(address) — sem dinâmico.
  Uint8List buildAddDeviceCalldata(EthereumAddress device) {
    final selector = keccak256(
            Uint8List.fromList(utf8.encode('addDevice(address)')))
        .sublist(0, 4);
    return (BytesBuilder()
          ..add(selector)
          ..add(_addressBytes(device)))
        .toBytes();
  }

  // Calldata de TruthIDAccount.execute(address,uint256,bytes) — 1 parâmetro
  // dinâmico (func), sempre o último. Usado como wrapper pra rotear qualquer
  // chamada (commitDevice, configureGuardians) através da smart account.
  Uint8List buildExecuteCalldata({
    required EthereumAddress dest,
    required BigInt value,
    required Uint8List func,
  }) {
    final selector = keccak256(Uint8List.fromList(
            utf8.encode('execute(address,uint256,bytes)')))
        .sublist(0, 4);
    final paddedFuncLen = ((func.length + 31) ~/ 32) * 32;

    final callData = BytesBuilder()
      ..add(selector)
      ..add(_addressBytes(dest))
      ..add(_uint256BytesFromBigInt(value))
      ..add(_uint256Bytes(96)) // offset do param dinâmico: 3*32
      ..add(_uint256Bytes(func.length))
      ..add(func)
      ..add(Uint8List(paddedFuncLen - func.length));

    return callData.toBytes();
  }

  // Calldata de TruthIDAccount.executeBatch(address[],uint256[],bytes[]) —
  // 3 arrays dinâmicos; `func` é o mais complexo porque cada elemento
  // (bytes) é ele mesmo dinâmico, então carrega seu próprio offset relativo
  // dentro do bloco de `func`. Usado pro reveal do pareamento de device
  // (registerDevice + addDevice sempre juntos — nunca separar, ver P52/P53
  // em PENDING.md: um device "registrado" mas sem addDevice fica incapaz de
  // assinar qualquer UserOp pra própria conta).
  Uint8List buildExecuteBatchCalldata({
    required List<EthereumAddress> dest,
    required List<BigInt> value,
    required List<Uint8List> func,
  }) {
    assert(dest.length == value.length && value.length == func.length);
    final n = dest.length;
    final selector = keccak256(Uint8List.fromList(utf8.encode(
            'executeBatch(address[],uint256[],bytes[])')))
        .sublist(0, 4);

    // Cabeçalho: 3 offsets (dest, value, func), cada um relativo ao início
    // dos dados dos parâmetros (logo após o selector).
    final destOffset = 96; // 3 slots de cabeçalho * 32
    final destBlockLen = 32 + n * 32; // slot de length + n endereços
    final valueOffset = destOffset + destBlockLen;
    final valueBlockLen = 32 + n * 32; // slot de length + n uint256
    final funcOffset = valueOffset + valueBlockLen;

    // Bloco de `func`: slot de length + n offsets, seguido dos n elementos
    // bytes (cada um com seu próprio slot de length + dados com padding).
    // Achado real (P68, fatia 2): os offsets de `func[i]` são relativos ao
    // INÍCIO da tabela de offsets (logo após o slot de length, não depois
    // dela) — a 1ª versão começava a contagem em `32 + n*32` (depois da
    // tabela inteira), divergindo do vetor viem real por exatamente
    // `n*32` bytes. Confirmado byte a byte contra `encodeFunctionData` do
    // viem: pra n=2, o 1º offset é `64` (= n*32), não `96`.
    final funcOffsetsTableLen = n * 32;
    final elementOffsets = <int>[];
    final elementBlocks = <Uint8List>[];
    var runningOffset = funcOffsetsTableLen;
    for (final f in func) {
      elementOffsets.add(runningOffset);
      final paddedLen = ((f.length + 31) ~/ 32) * 32;
      final block = BytesBuilder()
        ..add(_uint256Bytes(f.length))
        ..add(f)
        ..add(Uint8List(paddedLen - f.length));
      final blockBytes = block.toBytes();
      elementBlocks.add(blockBytes);
      runningOffset += blockBytes.length;
    }

    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256Bytes(destOffset))
      ..add(_uint256Bytes(valueOffset))
      ..add(_uint256Bytes(funcOffset))
      // bloco dest[]
      ..add(_uint256Bytes(n));
    for (final d in dest) {
      callData.add(_addressBytes(d));
    }
    // bloco value[]
    callData.add(_uint256Bytes(n));
    for (final v in value) {
      callData.add(_uint256BytesFromBigInt(v));
    }
    // bloco func[]
    callData.add(_uint256Bytes(n));
    for (final offset in elementOffsets) {
      callData.add(_uint256Bytes(offset));
    }
    for (final block in elementBlocks) {
      callData.add(block);
    }

    return callData.toBytes();
  }

  // Calldata de RecoveryManager.configureGuardians(string,address[],uint256)
  // — mesmo padrão de buildCreateIdentityCalldata (1 string dinâmica entre
  // estáticos) + um array dinâmico (guardians).
  Uint8List buildConfigureGuardiansCalldata({
    required String username,
    required List<EthereumAddress> guardians,
    required BigInt threshold,
  }) {
    final selector = keccak256(Uint8List.fromList(utf8.encode(
            'configureGuardians(string,address[],uint256)')))
        .sublist(0, 4);

    final usernameBytes = Uint8List.fromList(utf8.encode(username));
    final paddedUsernameLen = ((usernameBytes.length + 31) ~/ 32) * 32;
    final usernameBlockLen = 32 + paddedUsernameLen; // length slot + dados

    final usernameOffset = 96; // 3 slots de cabeçalho * 32
    final guardiansOffset = usernameOffset + usernameBlockLen;

    final callData = BytesBuilder()
      ..add(selector)
      ..add(_uint256Bytes(usernameOffset))
      ..add(_uint256Bytes(guardiansOffset))
      ..add(_uint256BytesFromBigInt(threshold))
      // bloco username (string)
      ..add(_uint256Bytes(usernameBytes.length))
      ..add(usernameBytes)
      ..add(Uint8List(paddedUsernameLen - usernameBytes.length))
      // bloco guardians (address[])
      ..add(_uint256Bytes(guardians.length));
    for (final g in guardians) {
      callData.add(_addressBytes(g));
    }

    return callData.toBytes();
  }

  // Endereço previsto (CREATE2) da smart account de um owner, lido direto da
  // view on-chain da factory — única fonte de verdade usada neste app pra
  // esse endereço (P68, fatia 1). Nunca replicar o cálculo de CREATE2
  // localmente: foi exatamente isso que causou o bug real do P66 no Desktop
  // (bytecode copiado ficou desatualizado após um redeploy da factory,
  // endereço previsto localmente divergiu do real). `index` é sempre 0 nesta
  // app — mesma convenção do Desktop (CreateIdentity.tsx sempre usa index 0).
  Future<EthereumAddress> predictSmartAccountAddress(
      EthereumAddress owner) async {
    final fn = _factoryContract.function('getAddress');
    final result = await _ethCall(
      _truthidAccountFactoryAddress,
      fn,
      [owner, BigInt.zero],
    );
    return result[0] as EthereumAddress;
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

  // eth_getTransactionReceipt, mas sem lançar pra tx ainda pendente (não
  // minerada) — só pra saber "já terminou, e deu certo?" via polling, sem
  // precisar de try/catch a cada rodada. Usado por CreateIdentityScreen
  // (P68, fatia 1) entre cada transação da sequência, já que
  // `eth_sendTransaction` via WalletConnect devolve só o hash, não o recibo.
  // null = ainda pendente; true = minerada com sucesso (status 0x1); false =
  // minerada mas revertida (status 0x0).
  Future<bool?> isTransactionConfirmed(String txHash) async {
    final result = await _rpcCall('eth_getTransactionReceipt', [txHash]);
    if (result == null) return null;
    final map = result as Map<String, dynamic>;
    return (map['status'] as String) == '0x1';
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

  // ── Social Recovery (RecoveryManager) — leituras ──────────────────────────
  // (escrita de configureGuardians fica em buildConfigureGuardiansCalldata,
  // acima — propor/aprovar/executar/cancelar recovery de OUTRA identidade
  // continua exclusivo do Desktop, ver P75 em PENDING.md)

  /// Retorna a config de guardians de uma identidade: lista de endereços +
  /// threshold (M de N). Retorna null se nunca foi configurado (tupla vazia).
  Future<({List<String> guardians, BigInt threshold})?> getGuardianConfig(
      String username) async {
    try {
      final fn = _recoveryContract.function('getGuardianConfig');
      final result = await _ethCall(
          _recoveryManagerAddress, fn, [username]);
      final tuple = result[0] as List<dynamic>;
      final guardians = (tuple[0] as List<dynamic>)
          .map((g) => (g as EthereumAddress).hex)
          .toList();
      if (guardians.isEmpty) return null;
      return (guardians: guardians, threshold: tuple[1] as BigInt);
    } catch (_) {
      return null;
    }
  }

  /// Retorna a proposta ativa (se houver). Retorna null se nunca houve
  /// proposta, ou se a proposta foi executada/cancelada.
  /// Usado pela UI pra mostrar status de recovery em andamento.
  Future<RecoveryProposal?> getProposal(String username) async {
    try {
      final fn = _recoveryContract.function('getProposal');
      final result = await _ethCall(
          _recoveryManagerAddress, fn, [username]);
      final tuple = result[0] as List<dynamic>;
      final exists = tuple[6] as bool;
      if (!exists) return null;
      return RecoveryProposal(
        proposedBy: (tuple[0] as EthereumAddress).hex,
        newController: (tuple[1] as EthereumAddress).hex,
        proposedAt: tuple[2] as BigInt,
        approvalCount: tuple[3] as BigInt,
        executed: tuple[4] as bool,
        cancelled: tuple[5] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  /// Retorna o timelock do RecoveryManager (em segundos, tipicamente 7 dias).
  Future<BigInt?> getTimelock() async {
    try {
      final fn = _recoveryContract.function('TIMELOCK');
      final result = await _ethCall(_recoveryManagerAddress, fn, []);
      return result[0] as BigInt;
    } catch (_) {
      return null;
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

// Proposta de recovery social lida do RecoveryManager. O Mobile só escreve
// configureGuardians (P68, fatia 2, owner-gated via WalletConnect) — propor/
// aprovar/executar/cancelar recovery de OUTRA identidade como guardian segue
// exclusivo do Desktop (não é owner-gated, mas fora de escopo desta rodada;
// ver P75 em PENDING.md).
class RecoveryProposal {
  final String proposedBy;
  final String newController;
  final BigInt proposedAt;
  final BigInt approvalCount;
  final bool executed;
  final bool cancelled;

  const RecoveryProposal({
    required this.proposedBy,
    required this.newController,
    required this.proposedAt,
    required this.approvalCount,
    required this.executed,
    required this.cancelled,
  });
}

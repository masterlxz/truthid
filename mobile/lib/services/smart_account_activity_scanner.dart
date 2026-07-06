import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import '../models/smart_account_activity.dart';
import 'blockchain_service.dart';

// Porta de desktop/src/utils/scanSmartAccountActivity.ts (14.10) pra Dart —
// varre os eventos de sessão/device de uma identidade, do bloco `fromBlock`
// até `toBlock` (inclusive), em chunks de `_chunkSize` blocos, pra frente.
// Escala esperada é dezenas de operações por identidade (mesmo raciocínio do
// original), então receipts/blocks são buscados sequencialmente, não em
// paralelo — mais simples de deduplicar corretamente por hash/bloco sem
// lidar com corrida entre buscas concorrentes.
class SmartAccountActivityScanner {
  final BlockchainService _blockchainService;

  // Mesmo valor já validado contra RPCs públicos da Base — ver
  // BlockchainService._maxLogRangeBlocks e o comentário equivalente no
  // scanner do Desktop ("query exceeds max block range").
  static const _chunkSize = 2000;

  SmartAccountActivityScanner({BlockchainService? blockchainService})
      : _blockchainService = blockchainService ?? BlockchainService();

  static String _topic0(String eventSignature) {
    final sigBytes = keccak256(Uint8List.fromList(utf8.encode(eventSignature)));
    return '0x${sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  // Todos os 5 eventos indexam `identityId` em topic[1] — o filtro de topics
  // já deixa o RPC descartar eventos de outras identidades, o scanner nunca
  // busca-e-descarta nada. VaultUpdated fica de fora (VaultRegistry ainda não
  // deployado — mesma decisão do Desktop, ver smart_account_activity.dart).
  static final _eventSources = [
    _EventSource(
      address: BlockchainService.deviceRegistryAddress,
      topic0: _topic0('DeviceRegistered(uint256,address,string)'),
      type: SmartAccountActivityType.deviceRegistered,
    ),
    _EventSource(
      address: BlockchainService.deviceRegistryAddress,
      topic0: _topic0('DeviceRevoked(uint256,address)'),
      type: SmartAccountActivityType.deviceRevoked,
    ),
    _EventSource(
      address: BlockchainService.sessionRegistryAddress,
      topic0: _topic0('SessionCreated(uint256,bytes32,address)'),
      type: SmartAccountActivityType.sessionCreated,
    ),
    _EventSource(
      address: BlockchainService.sessionRegistryAddress,
      topic0: _topic0('SessionRevoked(uint256,bytes32)'),
      type: SmartAccountActivityType.sessionRevoked,
    ),
    _EventSource(
      address: BlockchainService.sessionRegistryAddress,
      topic0: _topic0('AllSessionsRevoked(uint256,uint256)'),
      type: SmartAccountActivityType.sessionRevokedAll,
    ),
  ];

  Future<List<SmartAccountActivity>> scan({
    required BigInt identityId,
    required int fromBlock,
    required int toBlock,
    void Function(List<SmartAccountActivity> activitiesSoFar, ScanProgress progress)?
        onChunkScanned,
  }) async {
    final idTopic = '0x${identityId.toRadixString(16).padLeft(64, '0')}';
    final receiptCache = <String, TxReceiptInfo>{};
    final blockTimestampCache = <int, int>{};
    final activities = <SmartAccountActivity>[];

    var chunkFrom = fromBlock;
    while (chunkFrom <= toBlock) {
      final chunkTo = chunkFrom + _chunkSize - 1 > toBlock ? toBlock : chunkFrom + _chunkSize - 1;

      final logsPerSource = await Future.wait(_eventSources.map((source) async {
        final logs = await _blockchainService.getLogs(
          address: source.address,
          topics: [source.topic0, idTopic],
          fromBlock: chunkFrom,
          toBlock: chunkTo,
        );
        return logs.map((log) => (log: log, type: source.type)).toList();
      }));

      for (final entry in logsPerSource.expand((x) => x)) {
        final log = entry.log;
        final hash = log['transactionHash'] as String;
        final blockNumber = _hexToInt(log['blockNumber'] as String);
        final logIndex = _hexToInt(log['logIndex'] as String);

        var receipt = receiptCache[hash];
        if (receipt == null) {
          receipt = await _blockchainService.getTransactionReceipt(hash);
          receiptCache[hash] = receipt;
        }

        var timestamp = blockTimestampCache[blockNumber];
        if (timestamp == null) {
          timestamp = await _blockchainService.getBlockTimestamp(blockNumber);
          blockTimestampCache[blockNumber] = timestamp;
        }

        activities.add(SmartAccountActivity(
          type: entry.type,
          hash: hash,
          blockNumber: blockNumber,
          logIndex: logIndex,
          timestamp: timestamp,
          costWei: receipt.gasUsed * receipt.effectiveGasPrice,
        ));
      }

      activities.sort((a, b) => a.blockNumber != b.blockNumber
          ? a.blockNumber.compareTo(b.blockNumber)
          : a.logIndex.compareTo(b.logIndex));

      onChunkScanned?.call(
        List.of(activities),
        ScanProgress(scannedTo: chunkTo, latest: toBlock),
      );

      chunkFrom = chunkTo + 1;
    }

    return activities;
  }

  static int _hexToInt(String hex) => int.parse(hex.substring(2), radix: 16);
}

class _EventSource {
  final String address;
  final String topic0;
  final SmartAccountActivityType type;

  const _EventSource({required this.address, required this.topic0, required this.type});
}

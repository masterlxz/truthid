import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';

import 'package:truthid_mobile/models/smart_account_activity.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/smart_account_activity_scanner.dart';

class MockBlockchainService extends Mock implements BlockchainService {}

// Mesmo cálculo de topic0 usado internamente pelo scanner (duplicado aqui de
// propósito — o util é privado ao scanner, e recomputar no teste também
// serve como uma checagem cruzada independente da assinatura do evento).
String _topic0(String eventSignature) {
  final sigBytes = keccak256(Uint8List.fromList(utf8.encode(eventSignature)));
  return '0x${sigBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

// Um log inclui `topics: [topic0, idTopic]` porque a Sessão 122 juntou as 5
// fontes numa chamada só de getLogs — o scanner agora descobre o tipo de
// cada atividade pelo próprio topic0 do log, não mais por qual chamada
// (separada) devolveu o resultado.
Map<String, dynamic> _log({
  required String topic0,
  required String txHash,
  required int blockNumber,
  required int logIndex,
}) {
  return {
    'topics': [topic0],
    'transactionHash': txHash,
    'blockNumber': '0x${blockNumber.toRadixString(16)}',
    'logIndex': '0x${logIndex.toRadixString(16)}',
  };
}

void main() {
  late MockBlockchainService mockBlockchain;
  late SmartAccountActivityScanner scanner;

  final sessionCreatedTopic = _topic0('SessionCreated(uint256,bytes32,address)');
  final sessionRevokedTopic = _topic0('SessionRevoked(uint256,bytes32)');
  final deviceRegisteredTopic = _topic0('DeviceRegistered(uint256,address,string)');

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<dynamic>[]);
  });

  setUp(() {
    mockBlockchain = MockBlockchainService();
    scanner = SmartAccountActivityScanner(blockchainService: mockBlockchain);

    // Por padrão, a chamada combinada não devolve nada — cada teste
    // sobrescreve só o que precisa.
    when(() => mockBlockchain.getLogs(
          addresses: any(named: 'addresses'),
          topics: any(named: 'topics'),
          fromBlock: any(named: 'fromBlock'),
          toBlock: any(named: 'toBlock'),
        )).thenAnswer((_) async => []);
  });

  void mockLogsForChunk(int fromBlock, int toBlock, List<Map<String, dynamic>> logs) {
    when(() => mockBlockchain.getLogs(
          addresses: any(named: 'addresses'),
          topics: any(named: 'topics'),
          fromBlock: fromBlock,
          toBlock: toBlock,
        )).thenAnswer((_) async => logs);
  }

  test('escaneia um único evento num único chunk e calcula o custo corretamente',
      () async {
    mockLogsForChunk(0, 100, [
      _log(topic0: sessionCreatedTopic, txHash: '0xTx1', blockNumber: 100, logIndex: 0),
    ]);
    when(() => mockBlockchain.getTransactionReceipt('0xTx1')).thenAnswer(
      (_) async => TxReceiptInfo(
        gasUsed: BigInt.from(21000),
        effectiveGasPrice: BigInt.from(1000000000),
      ),
    );
    when(() => mockBlockchain.getBlockTimestamp(100))
        .thenAnswer((_) async => 1751000000);

    final activities = await scanner.scan(
      identityId: BigInt.one,
      fromBlock: 0,
      toBlock: 100,
    );

    expect(activities, hasLength(1));
    expect(activities.single.type, SmartAccountActivityType.sessionCreated);
    expect(activities.single.hash, '0xTx1');
    expect(activities.single.blockNumber, 100);
    expect(activities.single.timestamp, 1751000000);
    expect(activities.single.costWei, BigInt.from(21000) * BigInt.from(1000000000));
  });

  test('ordena atividades de tipos diferentes por (blockNumber, logIndex)',
      () async {
    mockLogsForChunk(0, 300, [
      _log(topic0: sessionCreatedTopic, txHash: '0xTxLater', blockNumber: 200, logIndex: 0),
      _log(topic0: deviceRegisteredTopic, txHash: '0xTxEarlier', blockNumber: 100, logIndex: 0),
    ]);
    when(() => mockBlockchain.getTransactionReceipt(any())).thenAnswer(
      (_) async => TxReceiptInfo(gasUsed: BigInt.one, effectiveGasPrice: BigInt.one),
    );
    when(() => mockBlockchain.getBlockTimestamp(any()))
        .thenAnswer((_) async => 1751000000);

    final activities = await scanner.scan(
      identityId: BigInt.one,
      fromBlock: 0,
      toBlock: 300,
    );

    expect(activities, hasLength(2));
    expect(activities[0].hash, '0xTxEarlier');
    expect(activities[1].hash, '0xTxLater');
  });

  test('deduplica receipt e timestamp quando dois eventos compartilham tx/bloco',
      () async {
    mockLogsForChunk(0, 100, [
      _log(topic0: sessionCreatedTopic, txHash: '0xSharedTx', blockNumber: 100, logIndex: 0),
      _log(topic0: sessionRevokedTopic, txHash: '0xSharedTx', blockNumber: 100, logIndex: 1),
    ]);
    when(() => mockBlockchain.getTransactionReceipt('0xSharedTx')).thenAnswer(
      (_) async => TxReceiptInfo(gasUsed: BigInt.one, effectiveGasPrice: BigInt.one),
    );
    when(() => mockBlockchain.getBlockTimestamp(100))
        .thenAnswer((_) async => 1751000000);

    final activities = await scanner.scan(
      identityId: BigInt.one,
      fromBlock: 0,
      toBlock: 100,
    );

    expect(activities, hasLength(2));
    verify(() => mockBlockchain.getTransactionReceipt('0xSharedTx')).called(1);
    verify(() => mockBlockchain.getBlockTimestamp(100)).called(1);
  });

  test('escaneia em chunks de 2000 blocos ao cruzar o limite de uma faixa, uma chamada por chunk',
      () async {
    final activities = await scanner.scan(
      identityId: BigInt.one,
      fromBlock: 1000,
      toBlock: 3500,
    );
    expect(activities, isEmpty);

    // Sessão 122: 1 chamada combinada por chunk (não mais 5 por fonte) ×
    // 2 chunks (1000-2999, 3000-3500) = 2 chamadas.
    final calls = verify(() => mockBlockchain.getLogs(
          addresses: any(named: 'addresses'),
          topics: any(named: 'topics'),
          fromBlock: captureAny(named: 'fromBlock'),
          toBlock: captureAny(named: 'toBlock'),
        )).captured;

    expect(calls, hasLength(4)); // 2 chamadas × 2 args capturados cada

    final fromBlocks = <int>{};
    final toBlocks = <int>{};
    for (var i = 0; i < calls.length; i += 2) {
      fromBlocks.add(calls[i] as int);
      toBlocks.add(calls[i + 1] as int);
    }
    expect(fromBlocks, {1000, 3000});
    expect(toBlocks, {2999, 3500});
  });

  test('combina os 5 topic0s e os 2 endereços numa chamada só por chunk', () async {
    await scanner.scan(identityId: BigInt.one, fromBlock: 0, toBlock: 100);

    final captured = verify(() => mockBlockchain.getLogs(
          addresses: captureAny(named: 'addresses'),
          topics: captureAny(named: 'topics'),
          fromBlock: any(named: 'fromBlock'),
          toBlock: any(named: 'toBlock'),
        )).captured;

    final addresses = captured[0] as List<String>;
    final topics = captured[1] as List<dynamic>;

    expect(addresses, hasLength(2)); // DeviceRegistry + SessionRegistry, deduplicados
    expect(topics, hasLength(2)); // [topic0List, idTopic]
    expect(topics[0], hasLength(5)); // 5 tipos de evento combinados via OR
  });

  test('chama onChunkScanned uma vez por chunk com o progresso correto',
      () async {
    final progressCalls = <ScanProgress>[];
    await scanner.scan(
      identityId: BigInt.one,
      fromBlock: 1000,
      toBlock: 3500,
      onChunkScanned: (_, progress) => progressCalls.add(progress),
    );

    expect(progressCalls, hasLength(2));
    expect(progressCalls[0].scannedTo, 2999);
    expect(progressCalls[0].latest, 3500);
    expect(progressCalls[1].scannedTo, 3500);
    expect(progressCalls[1].latest, 3500);
  });

  test('propaga erro se getLogs falhar', () async {
    when(() => mockBlockchain.getLogs(
          addresses: any(named: 'addresses'),
          topics: any(named: 'topics'),
          fromBlock: any(named: 'fromBlock'),
          toBlock: any(named: 'toBlock'),
        )).thenThrow(Exception('RPC error'));

    expect(
      () => scanner.scan(identityId: BigInt.one, fromBlock: 0, toBlock: 100),
      throwsException,
    );
  });

  test('propaga erro se getTransactionReceipt falhar', () async {
    mockLogsForChunk(0, 100, [
      _log(topic0: sessionCreatedTopic, txHash: '0xTx1', blockNumber: 100, logIndex: 0),
    ]);
    when(() => mockBlockchain.getTransactionReceipt('0xTx1'))
        .thenThrow(Exception('receipt not found'));

    expect(
      () => scanner.scan(identityId: BigInt.one, fromBlock: 0, toBlock: 100),
      throwsException,
    );
  });
}

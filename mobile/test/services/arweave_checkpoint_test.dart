import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_checkpoint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  // Mock por chave (não um único valor fixo, ao contrário do padrão usado
  // por ArweaveWalletService/VaultKeyService) — ArweaveCheckpointStore
  // grava uma entrada por hash de conteúdo, então o mock precisa rotear
  // read/write/delete pela chave real que o plugin recebe.
  Map<String, String> mockStorage() {
    final store = <String, String>{};
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        default:
          return null;
      }
    });
    return store;
  }

  PublishCheckpoint sample({required String contentHash, int nextChunkIndex = 1}) {
    return PublishCheckpoint(
      walletAddress: 'addr-de-teste',
      contentHash: contentHash,
      txId: 'tx-123',
      dataRoot: 'root-b64',
      dataSize: '1000',
      nodeUrl: 'https://arweave.net',
      totalChunks: 3,
      nextChunkIndex: nextChunkIndex,
    );
  }

  group('ArweaveCheckpointStore', () {
    test('load() retorna null quando não existe checkpoint pro hash', () async {
      mockStorage();
      const store = ArweaveCheckpointStore();
      expect(await store.load('hash-inexistente'), isNull);
    });

    test('save() então load() faz round-trip', () async {
      mockStorage();
      const store = ArweaveCheckpointStore();
      final cp = sample(contentHash: 'hash-abc');

      await store.save(cp);
      final loaded = await store.load('hash-abc');

      expect(loaded, isNotNull);
      expect(loaded!.txId, 'tx-123');
      expect(loaded.walletAddress, 'addr-de-teste');
      expect(loaded.totalChunks, 3);
      expect(loaded.nextChunkIndex, 1);
    });

    test('clear() remove o checkpoint', () async {
      mockStorage();
      const store = ArweaveCheckpointStore();
      await store.save(sample(contentHash: 'hash-xyz'));

      expect(await store.load('hash-xyz'), isNotNull);
      await store.clear('hash-xyz');
      expect(await store.load('hash-xyz'), isNull);
    });

    test('clear() em checkpoint que não existe não lança', () async {
      mockStorage();
      const store = ArweaveCheckpointStore();
      await store.clear('nunca-existiu');
    });

    test('checkpoints com hashes diferentes não colidem entre si', () async {
      final backing = mockStorage();
      const store = ArweaveCheckpointStore();

      await store.save(sample(contentHash: 'hash-1', nextChunkIndex: 0));
      await store.save(sample(contentHash: 'hash-2', nextChunkIndex: 2));

      expect(backing.length, 2, reason: 'cada hash vira sua própria entrada, não sobrescreve');
      expect((await store.load('hash-1'))!.nextChunkIndex, 0);
      expect((await store.load('hash-2'))!.nextChunkIndex, 2);

      await store.clear('hash-1');
      expect(await store.load('hash-1'), isNull);
      expect(await store.load('hash-2'), isNotNull, reason: 'limpar um hash não afeta o outro');
    });

    test('load() retorna null quando o JSON armazenado está corrompido', () async {
      final backing = mockStorage();
      // Escreve direto na chave real (mesmo formato usado internamente pela
      // store), simulando uma entrada corrompida em disco.
      backing['truthid_arweave_publish_checkpoint_hash-corrompido'] = 'não é json válido {{{';

      const store = ArweaveCheckpointStore();
      expect(await store.load('hash-corrompido'), isNull);
    });

    test('contentHashHex é determinístico e sensível ao conteúdo', () {
      final a = contentHashHex(Uint8List.fromList([1, 2, 3]));
      final b = contentHashHex(Uint8List.fromList([1, 2, 3]));
      final c = contentHashHex(Uint8List.fromList([1, 2, 4]));
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}

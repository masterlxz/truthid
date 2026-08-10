import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_merkle.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _repeat(int byte, int length) => Uint8List(length)..fillRange(0, length, byte);

void main() {
  group('arweave_merkle', () {
    test('dado vazio produz um chunk de tamanho zero', () {
      final chunks = chunkData(Uint8List(0));
      expect(chunks.length, 1);
      expect(chunks[0].minByteRange, 0);
      expect(chunks[0].maxByteRange, 0);
    });

    test('dado pequeno produz um chunk só', () {
      final data = _repeat(7, 1024);
      final chunks = chunkData(data);
      expect(chunks.length, 1);
      expect(chunks[0].maxByteRange, 1024);
    });

    test('exatamente maxChunkSize produz dois chunks', () {
      // maxChunkSize bytes entram no loop (rest.length >= max), sobra um
      // chunk vazio no final (mesmo comportamento do arweave-js).
      final data = _repeat(1, maxChunkSize);
      final chunks = chunkData(data);
      expect(chunks.length, 2);
      expect(chunks[0].maxByteRange, maxChunkSize);
      expect(chunks[1].minByteRange, maxChunkSize);
      expect(chunks[1].maxByteRange, maxChunkSize);
    });

    test('pouco acima de maxChunkSize rebalanceia pra evitar chunk minúsculo', () {
      final data = _repeat(1, maxChunkSize + 1);
      final chunks = chunkData(data);
      expect(chunks.length, 2);
      for (final c in chunks) {
        final len = c.maxByteRange - c.minByteRange;
        expect(len >= minChunkSize, isTrue, reason: 'chunk de $len bytes abaixo do mínimo');
      }
      expect(chunks.last.maxByteRange, data.length);
    });

    test('byte ranges multi-chunk são contíguos', () {
      final data = _repeat(9, maxChunkSize * 3 + 500);
      final chunks = chunkData(data);
      expect(chunks.length >= 3, isTrue);
      var expectedStart = 0;
      for (final c in chunks) {
        expect(c.minByteRange, expectedStart);
        expectedStart = c.maxByteRange;
      }
      expect(chunks.last.maxByteRange, data.length);
    });

    test('data_root é determinístico', () {
      final data = Uint8List.fromList(utf8.encode('hello vault blob'));
      final root1 = computeDataRoot(chunkData(data));
      final root2 = computeDataRoot(chunkData(data));
      expect(root1, equals(root2));
    });

    test('dados diferentes geram root diferente', () {
      final root1 = computeDataRoot(chunkData(Uint8List.fromList(utf8.encode('vault v1'))));
      final root2 = computeDataRoot(chunkData(Uint8List.fromList(utf8.encode('vault v2'))));
      expect(root1, isNot(equals(root2)));
    });

    // Vetores cross-checados contra arweave-js real (merkle.rs:359-362,
    // 434-436, já provados corretos numa sessão anterior do Desktop) —
    // reaproveitados literalmente.
    test('vetor cross-checado: root de um chunk só', () {
      final root = computeDataRoot(chunkData(Uint8List.fromList(utf8.encode('hello world'))));
      expect(_hex(root), '27780e22e3b3f356e8aba78732ce3217ce1f312874cafaca16a39c9d740c2fdd');
    });

    test('vetor cross-checado: root multi-chunk', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final root = computeDataRoot(chunkData(data));
      expect(_hex(root), 'fb70bd611bd95db03ae5e779316bc16940493b636908d7e4b9a90d837dcfa947');
    });

    test('vetor cross-checado: provas batem com arweave-js', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final (chunks, proofs) = chunkDataForUpload(data);
      expect(chunks.length, 3, reason: 'conteúdo não é múltiplo exato — não deve descartar nada');
      expect(proofs.length, 3);

      expect(proofs[0].offset, 262143);
      expect(
        _hex(proofs[0].proof),
        '84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa021304c16b5b3b0ac94b52784caf6c0f6f7fa76eacb9b4295087edc9da297b01bbf5dd864466f45523652fe3d6051cea17a669d863936d26f170964da1a47ffc0000000000000000000000000000000000000000000000000000000000040000c6a68609e7e9bf598a7e12a826337bd08f29200bc8c37f0c4ebe26b7dfc8c4be0000000000000000000000000000000000000000000000000000000000040000',
      );
      expect(proofs[1].offset, 393465);
      expect(
        _hex(proofs[1].proof),
        '84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa021304c16b5b3b0ac94b52784caf6c0f6f7fa76eacb9b4295087edc9da297b01bbf5dd864466f45523652fe3d6051cea17a669d863936d26f170964da1a47ffc00000000000000000000000000000000000000000000000000000000000400003ccde55fefef16e9aed69a5af49173818df5f730f6c08f0ee74c7217cdb96f4500000000000000000000000000000000000000000000000000000000000600fa',
      );
      expect(proofs[2].offset, 524787);
      expect(
        _hex(proofs[2].proof),
        '84634a0e6f233db7ba81986591e0e82d3878b7b8e373f8d92d00242508410f1d47be080793f0f5d282566f7af072a8b58dec3e111551fffa7eb8733ac9df7cd800000000000000000000000000000000000000000000000000000000000600fa3ccde55fefef16e9aed69a5af49173818df5f730f6c08f0ee74c7217cdb96f4500000000000000000000000000000000000000000000000000000000000801f4',
      );
    });

    // Teste de não-aliasing dedicado (ver comentário em _resolveBranchProofs):
    // se dois branches irmãos compartilhassem o mesmo buffer de prefixo
    // mutável, o teste acima (vetores cross-checados de 3 folhas) já falharia
    // — este teste é redundante de propósito, documenta explicitamente que a
    // ausência de aliasing é o que garante o resultado acima.
    test('provas de folhas irmãs não compartilham buffer mutado', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final (_, proofs) = chunkDataForUpload(data);
      // Cada prova deve ter conteúdo distinto (uma mutação vazada faria
      // duas provas convergirem ou corromperem de forma correlata).
      final hexes = proofs.map((p) => _hex(p.proof)).toSet();
      expect(hexes.length, proofs.length);
    });

    test('chunkDataForUpload descarta o chunk vazio final', () {
      // Múltiplo exato de maxChunkSize: chunkData() cru produz 2 chunks (o
      // segundo vazio). chunkDataForUpload deve descartar esse par, sobrando 1.
      final data = _repeat(0x11, maxChunkSize);
      final (chunks, proofs) = chunkDataForUpload(data);
      expect(chunks.length, 1);
      expect(proofs.length, 1);
      expect(chunks[0].maxByteRange, maxChunkSize);
    });

    test('chunkDataForUpload mantém chunks quando não é múltiplo exato', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final (chunks, proofs) = chunkDataForUpload(data);
      expect(chunks.length, 3);
      expect(proofs.length, 3);
    });

    test('validatePath aceita prova gerada por este módulo', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final (chunks, proofs) = chunkDataForUpload(data);
      final root = computeDataRoot(chunkData(data));

      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final proof = proofs[i];
        final result = validatePath(root, proof.offset, 0, data.length, proof.proof);
        expect(result, isNotNull, reason: 'prova gerada por generateProofs deveria validar');
        final (offset, leftBound, rightBound) = result!;
        expect(offset, chunk.maxByteRange - 1);
        expect(leftBound, chunk.minByteRange);
        expect(rightBound, chunk.maxByteRange);
      }
    });

    test('validatePath rejeita prova adulterada', () {
      final data = _repeat(0xAB, maxChunkSize * 2 + 500);
      final (_, proofs) = chunkDataForUpload(data);
      final root = computeDataRoot(chunkData(data));

      final tampered = Uint8List.fromList(proofs[0].proof);
      tampered[0] ^= 0xFF;
      expect(validatePath(root, proofs[0].offset, 0, data.length, tampered), isNull);
    });
  });
}

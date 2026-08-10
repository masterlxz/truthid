import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_deep_hash.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('arweave_deep_hash', () {
    test('hash de blob é determinístico', () {
      final a = deepHash(DeepHashChunk.utf8('hello'));
      final b = deepHash(DeepHashChunk.utf8('hello'));
      expect(a, equals(b));
    });

    test('blobs diferentes geram hash diferente', () {
      final a = deepHash(DeepHashChunk.utf8('hello'));
      final b = deepHash(DeepHashChunk.utf8('world'));
      expect(a, isNot(equals(b)));
    });

    test('blob vazio não gera hash zero', () {
      final h = deepHash(DeepHashChunk.blob(Uint8List(0)));
      expect(h, isNot(equals(Uint8List(48))));
    });

    test('lista vazia difere do blob vazio', () {
      final listHash = deepHash(DeepHashChunk.list(const []));
      final blobHash = deepHash(DeepHashChunk.blob(Uint8List(0)));
      expect(listHash, isNot(equals(blobHash)));
    });

    test('ordem da lista importa', () {
      final a = deepHash(DeepHashChunk.list([
        DeepHashChunk.utf8('a'),
        DeepHashChunk.utf8('b'),
      ]));
      final b = deepHash(DeepHashChunk.list([
        DeepHashChunk.utf8('b'),
        DeepHashChunk.utf8('a'),
      ]));
      expect(a, isNot(equals(b)));
    });

    test('lista aninhada difere da lista achatada', () {
      final nested = deepHash(DeepHashChunk.list([
        DeepHashChunk.list([
          DeepHashChunk.utf8('a'),
          DeepHashChunk.utf8('b'),
        ]),
      ]));
      final flat = deepHash(DeepHashChunk.list([
        DeepHashChunk.utf8('a'),
        DeepHashChunk.utf8('b'),
      ]));
      expect(nested, isNot(equals(flat)));
    });

    // Deep hash é SHA-384 (48 bytes) — distinto do SHA-256 (32 bytes) usado
    // no merkle data_root. Fácil de trocar sem querer durante o porte;
    // este teste pega isso cedo.
    test('saída tem 48 bytes (SHA-384, não 32 de SHA-256)', () {
      final h = deepHash(DeepHashChunk.utf8('x'));
      expect(h.length, 48);
    });

    // Vetores cross-checados contra arweave-js real (deep_hash.rs:147-150,
    // já provados corretos numa sessão anterior do Desktop) — reaproveitados
    // literalmente, sem precisar reinstalar nada pra essa parte.
    test('vetor cross-checado: blob "hello world"', () {
      final h = deepHash(DeepHashChunk.utf8('hello world'));
      expect(
        _hex(h),
        '42b60b0591c3817049a0658511314e57167cf2992b2c4d2013211707ab65dccf4e1a44fb385107290cf6bdb5e45455df',
      );
    });

    test('vetor cross-checado: lista ["2","hello","world"]', () {
      final h = deepHash(DeepHashChunk.list([
        DeepHashChunk.utf8('2'),
        DeepHashChunk.utf8('hello'),
        DeepHashChunk.utf8('world'),
      ]));
      expect(
        _hex(h),
        '7e6855103565e447a404995c77564e02174f2ce23bc351f950e7d801ed6eed0c06cfa3544df8a078dcd2d25fb3338248',
      );
    });
  });
}

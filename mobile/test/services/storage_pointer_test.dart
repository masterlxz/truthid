import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/storage_pointer.dart';

void main() {
  group('StoragePointerKind.of', () {
    test('reconhece ponteiro Arweave', () {
      expect(StoragePointerKind.of('ar://Abc123_-xyz'),
          StoragePointerKind.arweave);
    });

    test('reconhece ponteiro Git', () {
      expect(
          StoragePointerKind.of(
              'git:AQID@0123456789abcdef0123456789abcdef01234567'),
          StoragePointerKind.git);
    });

    test('CID sem esquema é IPFS legado', () {
      expect(
          StoragePointerKind.of('QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG'),
          StoragePointerKind.legacyIpfs);
      expect(
          StoragePointerKind.of(
              'bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi'),
          StoragePointerKind.legacyIpfs);
    });

    test('esquema desconhecido e string vazia continuam caindo em IPFS legado',
        () {
      expect(StoragePointerKind.of('http://example.com/x'),
          StoragePointerKind.legacyIpfs);
      expect(StoragePointerKind.of(''), StoragePointerKind.legacyIpfs);
    });

    test('o prefixo é literal: maiúsculas e prefixos parciais não contam', () {
      expect(StoragePointerKind.of('AR://x'), StoragePointerKind.legacyIpfs);
      expect(StoragePointerKind.of('xar://x'), StoragePointerKind.legacyIpfs);
      expect(StoragePointerKind.of('mygit:x'), StoragePointerKind.legacyIpfs);
    });
  });
}

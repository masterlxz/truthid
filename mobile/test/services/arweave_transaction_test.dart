import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:truthid_mobile/services/arweave_jwk.dart';
import 'package:truthid_mobile/services/arweave_transaction.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// last_tx/anchor de teste: precisa ser base64url válido (canônico) — um
// placeholder de texto arbitrário como "anchor123" falha ao decodificar
// (comprimento/bits inválidos) já que last_tx é sempre um hash real de 32
// bytes na rede de verdade. 32 bytes de 0xAA codificados em base64url.
const _testAnchor = 'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo';

void main() {
  final testWalletJson = File('test/fixtures/arweave/test_wallet.json').readAsStringSync();
  (pc.RSAPrivateKey, pc.RSAPublicKey) testWallet() {
    final jwk = parseJwk(testWalletJson);
    return jwkToKeyPair(jwk);
  }

  group('arweave_transaction', () {
    test('campos de buildTransaction estão corretos', () {
      final data = Uint8List.fromList(utf8.encode('hello vault'));
      final tx = buildTransaction(
        data,
        [('Content-Type', 'application/octet-stream')],
        '1000',
        'anchor123',
        'owner-n-b64',
      );
      expect(tx.format, 2);
      expect(tx.dataSize, data.length.toString());
      expect(tx.target, '');
      expect(tx.quantity, '0');
      expect(tx.dataRoot.isNotEmpty, isTrue);
      expect(tx.id.isEmpty, isTrue);
      expect(tx.signature.isEmpty, isTrue);
    });

    test('buildTransaction com dado vazio tem dataRoot vazio', () {
      final tx = buildTransaction(Uint8List(0), [], '1000', 'anchor123', 'owner-n-b64');
      expect(tx.dataRoot, '');
      expect(tx.dataSize, '0');
    });

    test('assina e verifica round-trip', () {
      final (priv, _) = testWallet();
      final jwk = parseJwk(testWalletJson);
      final tx = buildTransaction(
        Uint8List.fromList(utf8.encode('vault blob')),
        [],
        '1000',
        _testAnchor,
        jwk.n,
      );
      signTransaction(tx, priv);
      expect(tx.signature.isEmpty, isFalse);
      expect(tx.id.isEmpty, isFalse);
      expect(verifyTransactionSignature(tx), isTrue);
    });

    test('data_size adulterado falha na verificação', () {
      final (priv, _) = testWallet();
      final jwk = parseJwk(testWalletJson);
      final tx = buildTransaction(
        Uint8List.fromList(utf8.encode('vault blob')),
        [],
        '1000',
        _testAnchor,
        jwk.n,
      );
      signTransaction(tx, priv);
      tx.dataSize = '999999';
      expect(verifyTransactionSignature(tx), isFalse);
    });

    test('duas assinaturas da mesma tx não são bytes idênticos', () {
      // PSS usa salt aleatório — prova que a assinatura não está usando um
      // salt fixo/zerado por engano (bug histórico comum em wrappers PSS).
      final (priv, _) = testWallet();
      final jwk = parseJwk(testWalletJson);
      final tx1 = buildTransaction(
          Uint8List.fromList(utf8.encode('vault blob')), [], '1000', _testAnchor, jwk.n);
      final tx2 = buildTransaction(
          Uint8List.fromList(utf8.encode('vault blob')), [], '1000', _testAnchor, jwk.n);
      signTransaction(tx1, priv);
      signTransaction(tx2, priv);
      expect(tx1.signature, isNot(equals(tx2.signature)));
      expect(verifyTransactionSignature(tx1), isTrue);
      expect(verifyTransactionSignature(tx2), isTrue);
    });

    // Vetor cross-checado contra arweave-js (Transaction.getSignatureData()
    // real, com a wallet fixa de teste — transaction.rs:312-335, já provado
    // correto numa sessão anterior do Desktop) — valida a montagem exata dos
    // campos da tx e a ordem do deep hash, independente da aleatoriedade da
    // assinatura PSS em si.
    test('vetor cross-checado: signatureData bate com arweave-js', () {
      final jwk = parseJwk(testWalletJson);
      final data = Uint8List.fromList(utf8.encode('hello arweave vault'));
      final tx = buildTransaction(
        data,
        [
          ('Content-Type', 'application/octet-stream'),
          ('App-Name', 'TruthID'),
        ],
        '1234567',
        _testAnchor,
        jwk.n,
      );
      expect(tx.dataRoot, 'PUnf_1QCJMbVpivlLrf-vD1TBNd1ybPLch49PV0xGSo');
      expect(tx.dataSize, '19');

      final sigData = signatureData(tx);
      expect(
        _hex(sigData),
        '398db11889bb643a626352169e8f2f777faf98e94351daeaf8a6606135af364df1a936b8e80041b126acb39d67a95b24',
      );
    });

    test('toWireJson inclui data inline, toWireJsonNoData não', () {
      final jwk = parseJwk(testWalletJson);
      final tx = buildTransaction(
        Uint8List.fromList(utf8.encode('hi')),
        [('A', 'B')],
        '1000',
        _testAnchor,
        jwk.n,
      );
      final withData = tx.toWireJson();
      final withoutData = tx.toWireJsonNoData();

      expect(withData['data'], isNot(''));
      expect(withoutData['data'], '');
      // resto dos campos idêntico entre as duas variantes
      for (final key in ['format', 'id', 'last_tx', 'owner', 'target', 'quantity', 'data_size', 'data_root', 'reward', 'signature']) {
        expect(withData[key], withoutData[key]);
      }
      final tags = withData['tags'] as List;
      expect(tags.length, 1);
      expect((tags[0] as Map)['name'], isNotEmpty);
    });
  });
}

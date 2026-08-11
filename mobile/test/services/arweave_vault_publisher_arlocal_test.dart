// Validação de integração contra ArLocal do wrapper de alto nível
// `ArweaveVaultPublisher` (mobile/lib/services/arweave_client.dart) — mesma
// receita/infra do `arweave_arlocal_integration_test.dart` (cliente
// low-level), mas exercitando o caminho que a Etapa 2 do VaultPublishService
// realmente usa: carregar wallet da storage local + publicar (blob e
// documento) + conferir cid "ar://"+txId + contentHash keccak256. Mirror
// direto de `publish_vault_blob_round_trip_against_arlocal`/
// `publish_vault_document_round_trip_against_arlocal` (Rust, Sessões
// 187/189).
//
// Não roda no `flutter test` do dia a dia (tag `arlocal`, skip-by-default em
// dart_test.yaml). Rodar manualmente com ArLocal já no ar (ver docstring de
// arweave_arlocal_integration_test.dart pra receita completa):
//
//   flutter test --tags arlocal --run-skipped \
//     test/services/arweave_vault_publisher_arlocal_test.dart
@Tags(['arlocal'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart' show keccak256, bytesToHex;

import 'package:truthid_mobile/services/arweave_client.dart';
import 'package:truthid_mobile/services/arweave_jwk.dart';
import 'package:truthid_mobile/services/arweave_wallet_service.dart';

const _arlocalUrl = 'http://localhost:1984';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<void> _waitForArlocal(HttpClient client) async {
  for (var i = 0; i < 30; i++) {
    try {
      final response = await (await client.getUrl(Uri.parse('$_arlocalUrl/info'))).close();
      await response.drain<void>();
      if (response.statusCode == 200) return;
    } catch (_) {
      // ArLocal ainda não subiu — tenta de novo.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('ArLocal não respondeu em /info a tempo — está rodando em localhost:1984?');
}

Future<void> _mint(HttpClient client, String address, int winston) async {
  final response =
      await (await client.getUrl(Uri.parse('$_arlocalUrl/mint/$address/$winston'))).close();
  await response.drain<void>();
  if (response.statusCode != 200) {
    throw Exception('GET /mint retornou ${response.statusCode}');
  }
}

Future<void> _mine(HttpClient client) async {
  final response = await (await client.getUrl(Uri.parse('$_arlocalUrl/mine'))).close();
  await response.drain<void>();
  if (response.statusCode != 200) {
    throw Exception('GET /mine retornou ${response.statusCode}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding instala um HttpOverrides que faz todo
  // HttpClient devolver 400 sem tocar a rede (proteção padrão contra testes
  // "acidentalmente" de integração) — mas este arquivo É de integração de
  // propósito (ArLocal real). Sem isso, publish()/fetchData() nunca
  // chegariam a localhost:1984 de verdade.
  HttpOverrides.global = null;

  final fakeSecureStorage = <String, String>{};

  setUp(() {
    fakeSecureStorage.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'write':
          fakeSecureStorage[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'read':
          return fakeSecureStorage[call.arguments['key']];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('ArweaveVaultPublisher contra ArLocal real', () {
    test('publishVaultBlob: publica, mina, e o conteúdo publicado bate com o original', () async {
      final httpClient = HttpClient();
      await _waitForArlocal(httpClient);

      final jwk = generateJwk();
      final address = walletAddress(jwk);
      await _mint(httpClient, address, 1000000000000);
      fakeSecureStorage['truthid_arweave_wallet_jwk'] = jsonEncode(jwk.toJson());

      final publisher = ArweaveVaultPublisher(
        walletService: ArweaveWalletService(),
        nodeUrl: _arlocalUrl,
      );
      final content = Uint8List.fromList(utf8.encode('blob principal do vault, teste ArLocal'));
      final result = await publisher.publishVaultBlob(content);

      expect(result.cid, startsWith('ar://'));
      expect(result.contentHash, bytesToHex(keccak256(content), include0x: true));

      await _mine(httpClient);
      final txId = result.cid.substring('ar://'.length);
      final status = await getTxStatus(_arlocalUrl, txId);
      expect(status.confirmed, isTrue);

      final fetched = await fetchData(_arlocalUrl, txId);
      expect(fetched, content);

      httpClient.close();
    });

    test('publishDocument: publica com tags de documento, mina, e o conteúdo bate', () async {
      final httpClient = HttpClient();
      await _waitForArlocal(httpClient);

      final jwk = generateJwk();
      final address = walletAddress(jwk);
      await _mint(httpClient, address, 1000000000000);
      fakeSecureStorage['truthid_arweave_wallet_jwk'] = jsonEncode(jwk.toJson());

      final publisher = ArweaveVaultPublisher(
        walletService: ArweaveWalletService(),
        nodeUrl: _arlocalUrl,
      );
      final content = Uint8List.fromList(utf8.encode('conteudo do documento, teste ArLocal'));
      final result = await publisher.publishDocument(content, 'rg.pdf', 'application/pdf');

      expect(result.cid, startsWith('ar://'));
      expect(result.contentHash, bytesToHex(keccak256(content), include0x: true));

      await _mine(httpClient);
      final txId = result.cid.substring('ar://'.length);
      final fetched = await fetchData(_arlocalUrl, txId);
      expect(fetched, content);

      httpClient.close();
    });
  });
}

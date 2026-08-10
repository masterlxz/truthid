// Validação de integração contra ArLocal (rede Arweave local de dev) — não
// roda no `flutter test` do dia a dia (tag `arlocal`, configurada como
// skip-by-default em dart_test.yaml). Rodar manualmente:
//
//   1. Num diretório descartável: `npm install arweave` (não precisa de
//      overrides — só `arlocal` em si precisa fixar `arbundles`, ver receita
//      no `project/ROADMAP.md`).
//   2. `npm install arlocal@1.1.20` no mesmo diretório (com
//      `"overrides": {"arbundles": "0.6.12"}` no package.json, mesma receita
//      já usada nas sessões do Desktop) + `npx arlocal@1.1.20` (porta 1984).
//   3. `flutter test --tags arlocal --run-skipped
//      test/services/arweave_arlocal_integration_test.dart`
//
// Espelha `arweave::arlocal_tests` do cliente Rust
// (desktop/src-tauri/src/arweave/mod.rs) — mesma receita: gera wallet, funda
// via faucet, publica, minera manualmente, confirma, lê de volta. Só os 3
// cenários de round-trip (Etapa 1 do porte Dart é só o núcleo do cliente —
// os testes que passam por publish_vault_blob_with_jwk/publish_document
// equivalentes, wrappers de integração com o Vault, ficam pra Etapa 2).
@Tags(['arlocal'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/arweave_client.dart';
import 'package:truthid_mobile/services/arweave_jwk.dart';
import 'package:truthid_mobile/services/arweave_merkle.dart';

const _arlocalUrl = 'http://localhost:1984';

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

Uint8List _nonUniform(int size, int modulus) {
  final data = Uint8List(size);
  for (var i = 0; i < size; i++) {
    data[i] = i % modulus;
  }
  return data;
}

void main() {
  group('arweave_client contra ArLocal real', () {
    test('publish + fetch round-trip, conteúdo pequeno (inline)', () async {
      final client = HttpClient();
      await _waitForArlocal(client);

      final jwk = generateJwk();
      final address = walletAddress(jwk);
      await _mint(client, address, 1000000000000);

      final content = Uint8List.fromList(utf8.encode('vetor de teste real contra ArLocal'));
      final txId = await publish(_arlocalUrl, jwk, content, [('Test', 'arweave-dart-arlocal')]);

      await _mine(client);

      final status = await getTxStatus(_arlocalUrl, txId);
      expect(status.confirmed, isTrue, reason: 'tx deveria estar confirmada após minerar');

      final fetched = await fetchData(_arlocalUrl, txId);
      expect(fetched, content);

      client.close();
    });

    test('publish + fetch round-trip, conteúdo multi-chunk (>256KiB)', () async {
      final client = HttpClient();
      await _waitForArlocal(client);

      final jwk = generateJwk();
      final address = walletAddress(jwk);
      await _mint(client, address, 100000000000000);

      // Mesmo tamanho/padrão de conteúdo do vetor multi-chunk do Rust: 3
      // chunks reais (256KiB + ~128KiB rebalanceado + ~128KiB), conteúdo
      // não-uniforme pra parecer mais com um documento real.
      final size = maxChunkSize * 2 + 500;
      final content = _nonUniform(size, 251);

      final txId = await publish(_arlocalUrl, jwk, content, [('Test', 'arweave-dart-multi-chunk')]);

      await _mine(client);

      final status = await getTxStatus(_arlocalUrl, txId);
      expect(status.confirmed, isTrue, reason: 'tx deveria estar confirmada após minerar');

      final fetched = await fetchData(_arlocalUrl, txId);
      expect(fetched.length, content.length);
      expect(fetched, content);

      client.close();
    });

    test('publish + fetch round-trip, múltiplo exato de maxChunkSize', () async {
      final client = HttpClient();
      await _waitForArlocal(client);

      final jwk = generateJwk();
      final address = walletAddress(jwk);
      await _mint(client, address, 100000000000000);

      // Múltiplo exato de maxChunkSize (2x) — depois do descarte do chunk
      // final vazio, sobram exatamente 2 chunks reais. Prova contra um node
      // real que o descarte não deixa nenhum chunk vazio na fila de upload
      // nesse caso combinado.
      final size = maxChunkSize * 2;
      final content = _nonUniform(size, 199);

      final txId =
          await publish(_arlocalUrl, jwk, content, [('Test', 'arweave-dart-exact-double-chunk')]);

      await _mine(client);

      final status = await getTxStatus(_arlocalUrl, txId);
      expect(status.confirmed, isTrue, reason: 'tx deveria estar confirmada após minerar');

      final fetched = await fetchData(_arlocalUrl, txId);
      expect(fetched.length, content.length);
      expect(fetched, content);

      client.close();
    });
  });
}

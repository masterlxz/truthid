import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';

import 'ipns_key_service.dart';

// Configuração de um provider de pinning IPFS — mesma spec do Desktop
// (`desktop/src-tauri/src/ipfs.rs::PinningProvider`), configurado
// separadamente no Mobile (não há canal pra sincronizar API keys entre
// devices, ver PROJECT_STATE.md, Sessão 97).
//
// `kind` aceita dois valores:
//  - `"kubo"` — node Kubo (local ou remoto); usa `/api/v0/add` para upload
//  - `"psa"`  — IPFS Pinning Service API; usa `POST /pins` para fixar um CID
class PinningProvider {
  final String name;
  final String kind;
  final String endpointUrl;
  final String apiKey;

  const PinningProvider({
    required this.name,
    required this.kind,
    required this.endpointUrl,
    this.apiKey = '',
  });

  factory PinningProvider.fromJson(Map<String, dynamic> json) => PinningProvider(
        name: json['name'] as String,
        kind: json['kind'] as String,
        endpointUrl: json['endpoint_url'] as String,
        apiKey: json['api_key'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'endpoint_url': endpointUrl,
        'api_key': apiKey,
      };
}

// Resultado de pinVault: CID retornado pelo provider, hash do conteúdo (pro
// contrato VaultRegistry) e listas de providers que tiveram sucesso ou falha.
class PinResult {
  final String cid;
  final String contentHash;
  final List<String> providersOk;
  final List<String> providersFailed;

  const PinResult({
    required this.cid,
    required this.contentHash,
    required this.providersOk,
    required this.providersFailed,
  });
}

// Mirror em Dart de `desktop/src-tauri/src/ipfs.rs::pin_vault` — mesmo
// protocolo (Kubo `/api/v0/add` pra upload, PSA `/pins` pra fixar), só que
// via `dart:io HttpClient` puro (mesmo padrão já usado em
// `IpfsGatewayClient`, sem depender do pacote `http`).
class IpfsPinClient {
  Future<PinResult> pinVault(
    Uint8List content,
    List<PinningProvider> providers,
  ) async {
    final contentHash = bytesToHex(keccak256(content), include0x: true);

    final kubo = providers.where((p) => p.kind == 'kubo').toList();
    final psa = providers.where((p) => p.kind == 'psa').toList();

    if (kubo.isEmpty) {
      throw Exception(
        'nenhum provider Kubo configurado — faça o upload pelo menos via nó local',
      );
    }

    var cid = '';
    final providersOk = <String>[];
    final providersFailed = <String>[];

    // 1. Upload de conteúdo para cada Kubo node
    for (final p in kubo) {
      try {
        final c = await _kuboAdd(p.endpointUrl, content);
        if (cid.isEmpty) cid = c;
        providersOk.add(p.name);
      } catch (e) {
        providersFailed.add('${p.name}: $e');
      }
    }

    if (cid.isEmpty) {
      throw Exception(
        'todos os providers Kubo falharam: ${providersFailed.join('; ')}',
      );
    }

    // 2. Pinagem do CID em cada PSA provider
    for (final p in psa) {
      try {
        await _psaPin(p.endpointUrl, p.apiKey, cid);
        providersOk.add(p.name);
      } catch (e) {
        providersFailed.add('${p.name}: $e');
      }
    }

    return PinResult(
      cid: cid,
      contentHash: contentHash,
      providersOk: providersOk,
      providersFailed: providersFailed,
    );
  }

  // Publica `content` (já cifrado) num nome IPNS derivado deterministicamente
  // de `sessionIdHex` — dead-drop da 13.9, fatia 2a. Só funciona com
  // providers `kind == 'kubo'` (PSA não tem garantia de suportar publish de
  // IPNS, ver PROJECT_STATE.md Sessão 97); usa só o primeiro configurado, sem
  // redundância multi-provider nesta fatia. Devolve `null` sem lançar se não
  // houver nenhum provider Kubo — o dead-drop é best-effort, uma falha aqui
  // não pode derrubar o transporte LAN que roda em paralelo (ver
  // vault_session_screen.dart).
  //
  // Derivação validada contra um Kubo 0.42.0 real (não só round-trip
  // interno): o `Id` que `key/import` devolveu bateu byte-a-byte com
  // `IpnsKeyService.computeIpnsName` para o mesmo sessionId de teste.
  Future<String?> publishDeadDrop(
    String sessionIdHex,
    Uint8List content,
    List<PinningProvider> providers,
  ) async {
    final kubo = providers.where((p) => p.kind == 'kubo').toList();
    if (kubo.isEmpty) return null;

    final provider = kubo.first;
    final key = await deriveIpnsDeadDropKey(sessionIdHex);
    final keyName = 'truthid-dead-drop-$sessionIdHex';

    final cid = await _kuboAdd(provider.endpointUrl, content);
    await kuboImportKey(provider.endpointUrl, keyName, key.privateKeyProtobuf);
    try {
      await kuboPublishName(provider.endpointUrl, keyName, cid);
    } finally {
      // O registro assinado já propagou — não precisa manter a chave no
      // keystore do Kubo até o TTL (lifetime) do registro IPNS expirar.
      // Best-effort: falha aqui não invalida o publish que já aconteceu.
      try {
        await kuboRemoveKey(provider.endpointUrl, keyName);
      } catch (_) {}
    }

    return key.ipnsName;
  }

  // POST `{endpoint}/api/v0/key/import` com o protobuf da chave privada
  // (formato `libp2p-protobuf-cleartext`, o default do Kubo — não confundir
  // com o codec CIDv1 `libp2p-key`, são conceitos diferentes) como multipart.
  // Chave determinística (mesmo sessionId → mesmos bytes): se o Kubo já
  // tiver essa chave (ex: retry depois de o publish falhar mas antes do
  // key/rm rodar), trata "already exists" como sucesso em vez de lançar.
  Future<void> kuboImportKey(
    String endpointUrl,
    String keyName,
    Uint8List privateKeyProtobuf,
  ) async {
    final boundary = 'truthid-${DateTime.now().microsecondsSinceEpoch}';
    final client = HttpClient();
    try {
      final url = Uri.parse(
        '${_trimSlash(endpointUrl)}/api/v0/key/import'
        '?arg=${Uri.encodeQueryComponent(keyName)}'
        '&format=libp2p-protobuf-cleartext',
      );
      final request = await client.postUrl(url);
      request.headers
          .set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final head = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="key.bin"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n';
      final tail = '\r\n--$boundary--\r\n';

      request.add(utf8.encode(head));
      request.add(privateKeyProtobuf);
      request.add(utf8.encode(tail));

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!text.contains('already exists')) {
          throw Exception('kubo key/import retornou ${response.statusCode}: $text');
        }
      }
    } finally {
      client.close();
    }
  }

  // POST `{endpoint}/api/v0/name/publish` — publica `cid` sob `keyName`.
  // `lifetime=5m` cobre o TTL de sessão (3min, ver `SESSION_TTL_MS` na
  // extensão) com margem pra propagação de IPNS, que pode levar até ~1min.
  // Retorna o nome IPNS reportado pelo Kubo (campo `Name`) — deve bater com
  // `key.ipnsName` calculado antes, mas o call site usa o valor calculado
  // localmente, não este, pra não depender do formato de resposta do Kubo.
  Future<String> kuboPublishName(
    String endpointUrl,
    String keyName,
    String cid,
  ) async {
    final client = HttpClient();
    try {
      final url = Uri.parse(
        '${_trimSlash(endpointUrl)}/api/v0/name/publish'
        '?arg=${Uri.encodeQueryComponent('/ipfs/$cid')}'
        '&key=${Uri.encodeQueryComponent(keyName)}'
        '&lifetime=5m&ipns-base=base36',
      );
      final request = await client.postUrl(url);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('kubo name/publish retornou ${response.statusCode}: $text');
      }

      final json = jsonDecode(text) as Map<String, dynamic>;
      final name = json['Name'] as String?;
      if (name == null) {
        throw Exception('campo Name ausente: $text');
      }
      return name;
    } finally {
      client.close();
    }
  }

  // POST `{endpoint}/api/v0/key/rm` — limpeza best-effort depois do publish.
  Future<void> kuboRemoveKey(String endpointUrl, String keyName) async {
    final client = HttpClient();
    try {
      final url = Uri.parse(
        '${_trimSlash(endpointUrl)}/api/v0/key/rm'
        '?arg=${Uri.encodeQueryComponent(keyName)}&ipns-base=base36',
      );
      final request = await client.postUrl(url);
      final response = await request.close();
      await response.drain();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('kubo key/rm retornou ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  // POST `{endpoint}/api/v0/add` com o blob como multipart.
  // Retorna o CID (campo `Hash` na resposta JSON do Kubo).
  Future<String> _kuboAdd(String endpointUrl, Uint8List content) async {
    final boundary = 'truthid-${DateTime.now().microsecondsSinceEpoch}';
    final client = HttpClient();
    try {
      final url = Uri.parse('${_trimSlash(endpointUrl)}/api/v0/add');
      final request = await client.postUrl(url);
      request.headers
          .set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final head = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="vault.enc"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n';
      final tail = '\r\n--$boundary--\r\n';

      request.add(utf8.encode(head));
      request.add(content);
      request.add(utf8.encode(tail));

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain();
        throw Exception('kubo add retornou ${response.statusCode}');
      }

      final text = await response.transform(utf8.decoder).join();
      // Kubo pode retornar múltiplas linhas JSON; a última tem o hash raiz.
      final lines =
          text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) {
        throw Exception('resposta vazia do kubo');
      }
      final last = lines.last;
      final json = jsonDecode(last) as Map<String, dynamic>;
      final hash = json['Hash'] as String?;
      if (hash == null) {
        throw Exception('campo Hash ausente: $last');
      }
      return hash;
    } finally {
      client.close();
    }
  }

  // POST `{endpoint}/pins` com `{ cid, name }`.
  // 2xx ou 409 (já fixado) são tratados como sucesso.
  Future<void> _psaPin(String endpointUrl, String apiKey, String cid) async {
    final client = HttpClient();
    try {
      final url = Uri.parse('${_trimSlash(endpointUrl)}/pins');
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      if (apiKey.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $apiKey');
      }
      request.add(utf8.encode(jsonEncode({'cid': cid, 'name': 'truthid-vault'})));

      final response = await request.close();
      final status = response.statusCode;
      await response.drain();

      final ok = (status >= 200 && status < 300) || status == 409;
      if (!ok) {
        throw Exception('PSA pin retornou $status');
      }
    } finally {
      client.close();
    }
  }
}

String _trimSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

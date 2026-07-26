import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'vault_edit_dead_drop_key.dart';

const _defaultTimeout = Duration(seconds: 15);

String _trimSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

Future<HttpClientResponse> _postMultipart(
  HttpClient client,
  Uri url,
  String fieldName,
  String filename,
  Uint8List content,
  Duration timeout,
) async {
  const boundary = '----truthid-vault-edit-dead-drop';
  final body = BytesBuilder(copy: false)
    ..add(utf8.encode('--$boundary\r\n'))
    ..add(utf8.encode(
      'Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n',
    ))
    ..add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'))
    ..add(content)
    ..add(utf8.encode('\r\n--$boundary--\r\n'));
  final bytes = body.takeBytes();

  final request = await client.postUrl(url).timeout(timeout);
  request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
  request.headers.contentLength = bytes.length;
  request.add(bytes);
  return request.close().timeout(timeout);
}

// POST `{endpoint}/api/v0/add` — mirror of `IpfsPinClient`'s Kubo add (Rust)
// / `deadDropPublish.ts::kuboAdd`. Returns the CID (`Hash` field of Kubo's
// JSON response).
Future<String> _kuboAdd(
  HttpClient client,
  String endpointUrl,
  Uint8List content,
  Duration timeout,
) async {
  final response = await _postMultipart(
    client,
    Uri.parse('${_trimSlash(endpointUrl)}/api/v0/add'),
    'file',
    'vault-edit.enc',
    content,
    timeout,
  );
  final text = await response.transform(utf8.decoder).join().timeout(timeout);
  if (response.statusCode != 200) {
    throw StateError('kubo add returned ${response.statusCode}: $text');
  }
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) throw StateError('empty response from kubo');
  final json = jsonDecode(lines.last) as Map<String, dynamic>;
  final hash = json['Hash'] as String?;
  if (hash == null) throw StateError('missing Hash field: ${lines.last}');
  return hash;
}

// POST `{endpoint}/api/v0/key/import` — deterministic key (same sessionId ->
// same bytes): "already exists" is treated as success, not an error (e.g. a
// retry after a publish that failed before key/rm ran).
Future<void> _kuboImportKey(
  HttpClient client,
  String endpointUrl,
  String keyName,
  Uint8List privateKeyProtobuf,
  Duration timeout,
) async {
  final url = Uri.parse(
    '${_trimSlash(endpointUrl)}/api/v0/key/import'
    '?arg=${Uri.encodeComponent(keyName)}&format=libp2p-protobuf-cleartext',
  );
  final response = await _postMultipart(client, url, 'file', 'key.bin', privateKeyProtobuf, timeout);
  if (response.statusCode != 200) {
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    if (!text.contains('already exists')) {
      throw StateError('kubo key/import returned ${response.statusCode}: $text');
    }
  } else {
    await response.drain<void>();
  }
}

// POST `{endpoint}/api/v0/name/publish` — `lifetime=5m` covers the session
// TTL (up to 3min) with margin for IPNS propagation.
Future<void> _kuboPublishName(
  HttpClient client,
  String endpointUrl,
  String keyName,
  String cid,
  Duration timeout,
) async {
  final url = Uri.parse(
    '${_trimSlash(endpointUrl)}/api/v0/name/publish'
    '?arg=${Uri.encodeComponent('/ipfs/$cid')}&key=${Uri.encodeComponent(keyName)}'
    '&lifetime=5m&ipns-base=base36',
  );
  final request = await client.postUrl(url).timeout(timeout);
  final response = await request.close().timeout(timeout);
  final text = await response.transform(utf8.decoder).join().timeout(timeout);
  if (response.statusCode != 200) {
    throw StateError('kubo name/publish returned ${response.statusCode}: $text');
  }
}

// POST `{endpoint}/api/v0/key/rm` — best-effort cleanup after publish,
// called from a `finally` by the caller; a failure here never invalidates
// the publish that already happened.
Future<void> _kuboRemoveKey(
  HttpClient client,
  String endpointUrl,
  String keyName,
  Duration timeout,
) async {
  final url = Uri.parse(
    '${_trimSlash(endpointUrl)}/api/v0/key/rm?arg=${Uri.encodeComponent(keyName)}&ipns-base=base36',
  );
  final request = await client.postUrl(url).timeout(timeout);
  final response = await request.close().timeout(timeout);
  await response.drain<void>();
  if (response.statusCode != 200) {
    throw StateError('kubo key/rm returned ${response.statusCode}');
  }
}

/// Publishes [content] (already encrypted) to a deterministically-derived
/// IPNS name — dead-drop cross-network for a `vault-edit` proposal (P27),
/// mirror of `extension/src/vaultEdit/deadDropPublish.ts::publishDeadDrop`.
/// Best-effort: swallows any failure (no/unreachable Kubo endpoint, network
/// error, non-200 response) rather than throwing — this always runs in
/// parallel with the LAN push in [TruthIDRequester.vaultEdit] and must never
/// abort it.
Future<void> publishVaultEditDeadDrop(
  String sessionIdHex,
  Uint8List content,
  String endpointUrl, {
  Duration timeout = _defaultTimeout,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final key = await deriveVaultEditDeadDropKey(sessionIdHex);
    final keyName = 'truthid-vault-edit-dead-drop-$sessionIdHex';

    final cid = await _kuboAdd(client, endpointUrl, content, timeout);
    await _kuboImportKey(client, endpointUrl, keyName, key.privateKeyProtobuf, timeout);
    try {
      await _kuboPublishName(client, endpointUrl, keyName, cid, timeout);
    } finally {
      try {
        await _kuboRemoveKey(client, endpointUrl, keyName, timeout);
      } catch (_) {
        // best-effort, see _kuboRemoveKey doc above
      }
    }
  } catch (_) {
    // best-effort — see doc comment above
  } finally {
    client.close(force: true);
  }
}

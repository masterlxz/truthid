import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

import 'arweave_b64url.dart';
import 'arweave_isolate.dart';
import 'arweave_jwk.dart';
import 'arweave_merkle.dart';
import 'arweave_transaction.dart';

// Camada HTTP simples contra qualquer node/gateway Arweave — espelha
// mod.rs do cliente Rust (desktop/src-tauri/src/arweave/mod.rs). dart:io
// HttpClient puro (mesmo estilo de ipfs_pin_client.dart), não
// package:http, que não é dependência do projeto.
const String arweaveDefaultNode = 'https://arweave.net';

class TxStatus {
  const TxStatus(this.confirmed, this.blockHeight, this.numberOfConfirmations);
  final bool confirmed;
  final int? blockHeight;
  final int? numberOfConfirmations;
}

String _trimTrailingSlash(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

// `GET /price/{bytes}` — reward estimado em winston pra publicar `bytes`.
Future<String> getPrice(String nodeUrl, int bytes) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/price/$bytes');
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET /price retornou ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

// `GET /tx_anchor` — anchor recente pra usar como last_tx, evita replay.
Future<String> getTxAnchor(String nodeUrl) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/tx_anchor');
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET /tx_anchor retornou ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> _postTx(String nodeUrl, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/tx');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.transform(utf8.decoder).join();
      throw Exception('POST /tx retornou ${response.statusCode}: $text');
    }
    await response.drain<void>();
  } finally {
    client.close();
  }
}

// `POST /tx` — submete a transação assinada, com `data` inline no corpo
// JSON. Cobre conteúdo que cabe em 1 chunk (256KiB) — dados maiores usam
// submitTransactionNoData + submitChunk.
Future<void> submitTransaction(String nodeUrl, ArweaveTransaction tx) =>
    _postTx(nodeUrl, tx.toWireJson());

// `POST /tx` sem `data` inline — usado quando o conteúdo é maior que 1
// chunk e será enviado via POST /chunk separados.
Future<void> submitTransactionNoData(String nodeUrl, ArweaveTransaction tx) =>
    _postTx(nodeUrl, tx.toWireJsonNoData());

// `POST /chunk` — submete um chunk de conteúdo + sua prova de inclusão
// (data_path) na árvore de merkle da tx. offset/data_size sempre como
// string JSON (nunca número), confirmado contra a doc oficial e
// Transaction.getChunk() de arweave-js. Resposta de sucesso é texto puro
// "OK", não JSON — só lê o corpo no caminho de erro.
Future<void> submitChunk(
  String nodeUrl,
  String dataRoot,
  String dataSize,
  Proof proof,
  Uint8List chunkBytes,
) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/chunk');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'data_root': dataRoot,
      'data_size': dataSize,
      'data_path': b64UrlEncode(proof.proof),
      'chunk': b64UrlEncode(chunkBytes),
      'offset': proof.offset.toString(),
    }));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.transform(utf8.decoder).join();
      throw Exception('POST /chunk retornou ${response.statusCode}: $text');
    }
    await response.drain<void>();
  } finally {
    client.close();
  }
}

// `GET /tx/{id}/status` — 200 = confirmada (corpo tem block_height e
// number_of_confirmations); qualquer outro status = ainda pendente/não
// encontrada (não lança, só reporta confirmed=false).
Future<TxStatus> getTxStatus(String nodeUrl, String txId) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/tx/$txId/status');
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode == 200) {
      final text = await response.transform(utf8.decoder).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      return TxStatus(
        true,
        (json['block_height'] as num?)?.toInt(),
        (json['number_of_confirmations'] as num?)?.toInt(),
      );
    }
    await response.drain<void>();
    return const TxStatus(false, null, null);
  } finally {
    client.close();
  }
}

// `GET /{id}` — lê o conteúdo bruto publicado numa tx. Já remonta chunks
// automaticamente tanto no ArLocal quanto em gateway real.
Future<Uint8List> fetchData(String nodeUrl, String txId) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/$txId');
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET /{id} retornou ${response.statusCode}');
    }
    return await consolidateHttpClientResponseBytes(response);
  } finally {
    client.close();
  }
}

// `GET /wallet/{address}/balance` — saldo em winston.
Future<String> getWalletBalance(String nodeUrl, String address) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${_trimTrailingSlash(nodeUrl)}/wallet/$address/balance');
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET /wallet/{address}/balance retornou ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

// Orquestrador de ponta a ponta — preço, anchor, monta, assina, submete.
// Devolve o tx_id. Publica inline (POST /tx com data) se o conteúdo cabe
// em 1 chunk (≤256KiB); caso contrário, submete a tx sem data e faz upload
// em chunks reais via POST /chunk, sequencialmente — nunca concorrente
// (mesmo motivo do Rust: ArLocal deriva a ordem de remontagem por ordem de
// chegada, não pelo campo offset que o cliente envia; não é limitação de
// node real, mas o código não distingue hoje).
Future<String> publish(
  String nodeUrl,
  ArweaveJwk jwk,
  Uint8List content,
  List<(String, String)> tags,
) async {
  final reward = await getPrice(nodeUrl, content.length);
  final lastTx = await getTxAnchor(nodeUrl);

  final tx = buildTransaction(content, tags, reward, lastTx, jwk.n);
  // Assinatura RSA-PSS sempre roda em isolate dedicado — RSA-4096 puro em
  // Dart (pointycastle, sem aceleração nativa) trava a UI se rodar inline.
  await signTransactionInIsolate(tx, jwk);

  // Sanity check local antes de gastar uma requisição de rede: garante que
  // a tx não foi corrompida entre assinar e submeter.
  if (!verifyTransactionSignature(tx)) {
    throw Exception('assinatura da tx falhou na verificação local antes do submit');
  }

  final (chunks, proofs) = chunkDataForUpload(content);

  if (chunks.length <= 1) {
    await submitTransaction(nodeUrl, tx);
    return tx.id;
  }

  await submitTransactionNoData(nodeUrl, tx);

  final dataRootBytes = b64UrlDecodeStrict(tx.dataRoot);
  final total = chunks.length;
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    final proof = proofs[i];
    // Sanity check local antes de gastar a requisição — ArLocal não valida
    // a prova que o cliente manda, então esse é o único jeito de pegar um
    // bug sutil em generateProofs antes de mainnet (mesmo padrão de
    // verifyTransactionSignature acima).
    if (validatePath(dataRootBytes, proof.offset, 0, content.length, proof.proof) == null) {
      throw Exception(
          'tx ${tx.id} publicada, prova de merkle inválida localmente pro chunk $i/$total — não enviado');
    }

    final bytes = content.sublist(chunk.minByteRange, chunk.maxByteRange);
    try {
      await submitChunk(nodeUrl, tx.dataRoot, tx.dataSize, proof, bytes);
    } catch (e) {
      throw Exception('tx ${tx.id} publicada, chunk $i/$total falhou: $e');
    }
  }

  return tx.id;
}

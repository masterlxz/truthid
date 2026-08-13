import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Checkpoint de publish multi-chunk — mirror direto de checkpoint.rs
// (desktop/src-tauri/src/arweave/checkpoint.rs). Permite retomar um
// publish() que falhou no meio do envio de chunks em vez de deixar a tx
// presa on-chain incompleta pra sempre. Só cobre o caminho multi-chunk
// (chunks.length > 1); o caminho single-shot é uma única requisição,
// atômico o bastante sem precisar de checkpoint.
//
// Uma entrada por checkpoint no FlutterSecureStorage, chaveada pelo hash
// SHA-256 do conteúdo (não 1 entrada global) — permite mais de uma
// publicação multi-chunk parcial pendente ao mesmo tempo sem uma
// sobrescrever o progresso da outra. Mesmo padrão de storage de
// arweave_wallet_service.dart/pinning_provider_service.dart (cada serviço
// com sua própria instância/chave, sem "keyring" compartilhado).
class PublishCheckpoint {
  PublishCheckpoint({
    required this.walletAddress,
    required this.contentHash,
    required this.txId,
    required this.dataRoot,
    required this.dataSize,
    required this.nodeUrl,
    required this.totalChunks,
    required this.nextChunkIndex,
  });

  factory PublishCheckpoint.fromJson(Map<String, dynamic> json) => PublishCheckpoint(
        walletAddress: json['walletAddress'] as String,
        contentHash: json['contentHash'] as String,
        txId: json['txId'] as String,
        dataRoot: json['dataRoot'] as String,
        dataSize: json['dataSize'] as String,
        nodeUrl: json['nodeUrl'] as String,
        totalChunks: json['totalChunks'] as int,
        nextChunkIndex: json['nextChunkIndex'] as int,
      );

  final String walletAddress;
  final String contentHash;
  final String txId;
  final String dataRoot;
  final String dataSize;
  final String nodeUrl;
  final int totalChunks;
  int nextChunkIndex;

  Map<String, dynamic> toJson() => {
        'walletAddress': walletAddress,
        'contentHash': contentHash,
        'txId': txId,
        'dataRoot': dataRoot,
        'dataSize': dataSize,
        'nodeUrl': nodeUrl,
        'totalChunks': totalChunks,
        'nextChunkIndex': nextChunkIndex,
      };
}

String contentHashHex(Uint8List content) => sha256.convert(content).toString();

class ArweaveCheckpointStore {
  const ArweaveCheckpointStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String contentHash) => 'truthid_arweave_publish_checkpoint_$contentHash';

  // `null` tanto se a entrada não existir quanto se estiver corrompida —
  // nos dois casos, publish() deve tratar como "sem checkpoint
  // utilizável" e seguir como uma publicação nova, nunca falhar por causa
  // disso.
  Future<PublishCheckpoint?> load(String contentHash) async {
    final raw = await _storage.read(key: _key(contentHash));
    if (raw == null) return null;
    try {
      return PublishCheckpoint.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PublishCheckpoint cp) =>
      _storage.write(key: _key(cp.contentHash), value: jsonEncode(cp.toJson()));

  // Idempotente — não é erro tentar limpar um checkpoint que não existe
  // (ex.: caminho single-shot, que nunca cria um).
  Future<void> clear(String contentHash) => _storage.delete(key: _key(contentHash));
}

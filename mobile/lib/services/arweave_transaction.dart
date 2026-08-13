import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/export.dart' as pc;

import 'arweave_b64url.dart';
import 'arweave_deep_hash.dart';
import 'arweave_merkle.dart';

// Transação Arweave formato 2. Espelha `Transaction` de arweave-js
// (lib/transaction.ts) e transaction.rs do cliente Rust — mesmos nomes de
// campo, mesmo encoding (base64url sem padding pra tudo exceto `data`, que
// fica em bytes crus até a serialização final pro POST /tx).
//
// Mutável de propósito (campos não-final, `signTransaction` preenche
// `signature`/`id` in-place) — não é o estilo Dart mais idiomático, mas
// facilita diferenciar linha a linha contra o Rust durante o porte, que é
// a prioridade numa etapa de alto risco de bug silencioso.
class ArweaveTransaction {
  ArweaveTransaction({
    required this.format,
    this.id = '',
    required this.lastTx,
    required this.owner,
    required this.tags,
    this.target = '',
    this.quantity = '0',
    required this.dataRoot,
    required this.dataSize,
    required this.data,
    required this.reward,
    this.signature = '',
  });

  int format;
  String id;
  String lastTx;
  String owner;
  List<(String, String)> tags;
  String target;
  String quantity;
  String dataRoot;
  String dataSize;
  Uint8List data;
  String reward;
  String signature;

  // Corpo JSON compartilhado por toWireJson/toWireJsonNoData — só o campo
  // `data` muda entre as duas variantes, o resto é idêntico.
  Map<String, dynamic> _toWireJsonImpl(String dataB64) {
    final tagsJson = tags
        .map((t) => {
              'name': b64UrlEncode(Uint8List.fromList(utf8.encode(t.$1))),
              'value': b64UrlEncode(Uint8List.fromList(utf8.encode(t.$2))),
            })
        .toList();

    return {
      'format': format,
      'id': id,
      'last_tx': lastTx,
      'owner': owner,
      'tags': tagsJson,
      'target': target,
      'quantity': quantity,
      'data': dataB64,
      'data_size': dataSize,
      'data_root': dataRoot,
      'reward': reward,
      'signature': signature,
    };
  }

  // Corpo JSON pro POST /tx — mesmo formato de Transaction.toJSON() em
  // arweave-js: tudo em base64url (inclusive data e cada nome/valor de
  // tag), tags como lista de {name, value}. Só cobre conteúdo que caiba
  // em 1 chunk (data inline) — pra conteúdo maior, ver toWireJsonNoData.
  Map<String, dynamic> toWireJson() => _toWireJsonImpl(b64UrlEncode(data));

  // Mesmo corpo de toWireJson, mas com data vazio — usado quando o
  // conteúdo é publicado via POST /chunk em vez de inline (upload em
  // chunks). data_size/data_root continuam os valores reais; só o campo
  // data é zerado.
  Map<String, dynamic> toWireJsonNoData() => _toWireJsonImpl('');
}

// Monta a tx com target/quantity fixos (upload puro, sem transferência de
// valor) e calcula data_root. Ainda não assinada (id/signature vazios) —
// chamar signTransaction em seguida.
//
// Replica o caso especial de arweave-js prepareChunks: dado vazio usa
// dataRoot = "" (string vazia, não o hash de um chunk vazio) — evita
// computar merkle sobre "nada" só pra descartar depois.
ArweaveTransaction buildTransaction(
  Uint8List data,
  List<(String, String)> tags,
  String reward,
  String lastTx,
  String ownerNB64,
) {
  final dataRoot = data.isEmpty ? '' : b64UrlEncode(computeDataRoot(chunkData(data)));

  return ArweaveTransaction(
    format: 2,
    id: '',
    lastTx: lastTx,
    owner: ownerNB64,
    tags: tags,
    target: '',
    quantity: '0',
    dataRoot: dataRoot,
    dataSize: data.length.toString(),
    data: data,
    reward: reward,
    signature: '',
  );
}

// Monta a entrada do deep hash (formato 2) exatamente como
// Transaction.getSignatureData() em arweave-js: format, owner, target,
// quantity, reward, last_tx, tags (lista de pares [nome, valor] em bytes
// crus), data_size, data_root — nessa ordem.
Uint8List signatureData(ArweaveTransaction tx) {
  final ownerBytes = b64UrlDecodeStrict(tx.owner);
  final targetBytes = b64UrlDecodeStrict(tx.target);
  final lastTxBytes = b64UrlDecodeLenient(tx.lastTx);
  final dataRootBytes = b64UrlDecodeStrict(tx.dataRoot);

  final tagList = DeepHashChunk.list(tx.tags
      .map((t) => DeepHashChunk.list([DeepHashChunk.utf8(t.$1), DeepHashChunk.utf8(t.$2)]))
      .toList());

  final chunk = DeepHashChunk.list([
    DeepHashChunk.utf8(tx.format.toString()),
    DeepHashChunk.blob(ownerBytes),
    DeepHashChunk.blob(targetBytes),
    DeepHashChunk.utf8(tx.quantity),
    DeepHashChunk.utf8(tx.reward),
    DeepHashChunk.blob(lastTxBytes),
    tagList,
    DeepHashChunk.utf8(tx.dataSize),
    DeepHashChunk.blob(dataRootBytes),
  ]);
  return deepHash(chunk);
}

// Assina a tx: RSA-PSS/SHA-256 sobre o deep hash dos campos. Preenche
// signature e id (id = SHA-256(signature), base64url). PSS usa salt
// aleatório de 32 bytes por assinatura — duas assinaturas da mesma tx nunca
// são bit-a-bit iguais, só ambas válidas. Parâmetros (hash SHA-256, MGF1
// SHA-256, salt length 32) verificados nesta sessão contra um verificador
// RSA-PSS independente (Node/OpenSSL via `crypto.verify`, não pointycastle
// nem a reimplementação de verificação em JS do ArLocal).
void signTransaction(ArweaveTransaction tx, pc.RSAPrivateKey privateKey) {
  final sigData = signatureData(tx);
  final saltBytes = Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));

  final signer = pc.PSSSigner(pc.RSAEngine(), pc.SHA256Digest(), pc.SHA256Digest());
  signer.init(true, pc.ParametersWithSalt(pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey), saltBytes));
  final signature = signer.generateSignature(sigData);
  final sigBytes = signature.bytes;
  final idDigest = sha256.convert(sigBytes).bytes;

  tx.signature = b64UrlEncode(sigBytes);
  tx.id = b64UrlEncode(Uint8List.fromList(idDigest));
}

// Verificação local (RSA-PSS/SHA-256 contra o próprio deep hash) — só
// garante consistência interna (a tx não foi corrompida entre assinar e
// submeter), não confirma nada contra a rede real. `eB64` precisa ser o
// expoente público real da wallet (ArweaveJwk.e) — wallets importadas podem
// ter um expoente diferente de 65537 (o padrão que só generateJwk usa pra
// chaves novas), então não pode ser assumido aqui.
bool verifyTransactionSignature(ArweaveTransaction tx, String eB64) {
  final sigData = signatureData(tx);
  final n = _bytesToBigIntBE(b64UrlDecodeStrict(tx.owner));
  final e = _bytesToBigIntBE(b64UrlDecodeStrict(eB64));
  final pubKey = pc.RSAPublicKey(n, e);

  final verifier = pc.PSSSigner(pc.RSAEngine(), pc.SHA256Digest(), pc.SHA256Digest());
  // ParametersWithSaltConfiguration porque não sabemos o salt de antemão —
  // o verificador o recupera do bloco PSS decodificado; o SecureRandom
  // passado nunca é lido no caminho de verificação (só usado ao assinar).
  verifier.init(
    false,
    pc.ParametersWithSaltConfiguration(pc.PublicKeyParameter<pc.RSAPublicKey>(pubKey), pc.FortunaRandom(), 32),
  );

  final sigBytes = b64UrlDecodeStrict(tx.signature);
  return verifier.verifySignature(sigData, pc.PSSSignature(sigBytes));
}

BigInt _bytesToBigIntBE(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

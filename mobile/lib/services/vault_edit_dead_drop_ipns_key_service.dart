import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypt;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hkdf_util.dart';
import 'libp2p_key_util.dart' as libp2p;

/// Deriva o nome IPNS onde a extensão publica o dead-drop cross-network do
/// vault-edit (item 6 do backlog, `project/INDEX.md`) — mirror parcial de
/// `IpnsKeyService`, papel invertido: lá o Mobile publica e a extensão só
/// recomputa o nome público; aqui a **extensão** publica
/// (`extension/src/vaultEdit/deadDropIpnsKey.ts`) e o celular só precisa da
/// metade pública pra fazer `poll` — nunca vê nem precisa da chave privada.
///
/// `HKDF_SALT`/`HKDF_INFO` domain-separados dos usados por `IpnsKeyService`
/// (mesmo padrão do resto do projeto, ex: `VaultEditContentCipherService`
/// vs o cipher do `/pin`) — precisam bater byte-a-byte com
/// `extension/src/vaultEdit/deadDropIpnsKey.ts`.
const _hkdfSalt = 'TruthID Vault Edit IPNS';
const _hkdfInfo = 'dead-drop-key-v1';

/// Recalcula o nome IPNS (`k51...`) onde a extensão publica o dead-drop pra
/// esse `sessionId` (hex, já embutido no QR de `truthid-vault-edit`) — a
/// única informação em comum entre os dois lados. Montagem do protobuf/CID
/// compartilhada com `ipns_key_service.dart` via `libp2p_key_util.dart` —
/// só o HKDF salt/info (domain separation) é próprio deste namespace.
Future<String> computeIpnsNameForSession(String sessionIdHex) async {
  final sessionIdBytes = hexToBytes(sessionIdHex);
  final seed = hkdfSha256(
    ikm: sessionIdBytes,
    salt: utf8.encode(_hkdfSalt),
    info: utf8.encode(_hkdfInfo),
    length: 32,
  );

  final keyPair = await crypt.Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyProtobuf =
      libp2p.marshalKeyProtobuf(Uint8List.fromList(publicKey.bytes));

  return libp2p.computeIpnsNameFromPublicKeyProtobuf(publicKeyProtobuf);
}

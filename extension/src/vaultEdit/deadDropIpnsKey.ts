import { ed25519 } from '@noble/curves/ed25519';
import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';
import { base36 } from 'multiformats/bases/base36';
import { CID } from 'multiformats/cid';
import { create as createDigest } from 'multiformats/hashes/digest';

import { hexToBytes } from '../util/bytes';

/**
 * Deriva a chave IPNS pra dead-drop cross-network do vault-edit (item 6 do
 * backlog, `PROJECT_STATE.md`) — mirror de `session/ipnsKey.ts`, mas com
 * papel invertido: lá a extensão só recomputa o nome público (quem publica
 * é o Mobile, no pareamento de leitura). Aqui é a extensão quem publica
 * (tem o conteúdo pronto assim que a proposta é enfileirada), então precisa
 * da chave privada inteira, não só do nome.
 *
 * `HKDF_SALT`/`HKDF_INFO` são domain-separados dos usados em
 * `session/ipnsKey.ts` (mesmo padrão do resto do projeto, ex:
 * `vaultEdit/cipher.ts` vs o cipher do `/pin`) — evita que o mesmo
 * `sessionId` usado por acaso nos dois fluxos derive pro mesmo par de
 * chaves/nome IPNS. Precisam bater byte-a-byte com
 * `mobile/lib/services/vault_edit_dead_drop_ipns_key_service.dart`.
 */
const HKDF_SALT = new TextEncoder().encode('TruthID Vault Edit IPNS');
const HKDF_INFO = new TextEncoder().encode('dead-drop-key-v1');

const KEY_TYPE_ED25519 = 1;
const MULTICODEC_LIBP2P_KEY = 0x72;
const MULTIHASH_IDENTITY = 0x00;

export interface DeadDropKeyMaterial {
  /** Protobuf `PrivateKey` do libp2p, formato `libp2p-protobuf-cleartext` que o `key/import` do Kubo espera. */
  privateKeyProtobuf: Uint8Array;
  /** Nome IPNS (`k51...`) onde essa chave publica — mesmo valor que `computeDeadDropIpnsName` recalcula do lado Mobile. */
  ipnsName: string;
}

// Mensagem protobuf de 2 campos (`Type` varint, `Data` bytes) do
// `crypto.proto` do libp2p — igual pra PrivateKey e PublicKey. Só cobre o
// caso concreto usado aqui (Data sempre < 128 bytes, tag/length cabem num
// byte de varint cada), mesma limitação já aceita em
// `ipns_key_service.dart::_marshalKeyProtobuf`.
function marshalKeyProtobuf(data: Uint8Array): Uint8Array {
  if (data.length >= 128) {
    throw new Error('data too long for single-byte varint length');
  }
  return new Uint8Array([0x08, KEY_TYPE_ED25519, 0x12, data.length, ...data]);
}

function computeIpnsNameFromPublicKeyProtobuf(publicKeyProtobuf: Uint8Array): string {
  const digest = createDigest(MULTIHASH_IDENTITY, publicKeyProtobuf);
  const cid = CID.createV1(MULTICODEC_LIBP2P_KEY, digest);
  return cid.toString(base36.encoder);
}

/**
 * Deriva o par Ed25519 completo a partir do `sessionId` (hex) do QR e monta
 * o protobuf de chave privada pronto pra `POST /api/v0/key/import`, junto
 * com o nome IPNS resultante — orquestra os mesmos passos de
 * `deriveIpnsDeadDropKey` no Dart (`ipns_key_service.dart`).
 */
export function deriveDeadDropKey(sessionIdHex: string): DeadDropKeyMaterial {
  const sessionIdBytes = hexToBytes(sessionIdHex);
  const seed = hkdf(sha256, sessionIdBytes, HKDF_SALT, HKDF_INFO, 32);
  const publicKey = ed25519.getPublicKey(seed);

  // `Data` da PrivateKey protobuf do libp2p pra Ed25519 é seed(32) || pubkey(32) —
  // mesmo formato que `ed25519.PrivateKey` do Go usa, que é o que o Kubo espera.
  const privateKeyData = new Uint8Array(64);
  privateKeyData.set(seed, 0);
  privateKeyData.set(publicKey, 32);

  const publicKeyProtobuf = marshalKeyProtobuf(publicKey);

  return {
    privateKeyProtobuf: marshalKeyProtobuf(privateKeyData),
    ipnsName: computeIpnsNameFromPublicKeyProtobuf(publicKeyProtobuf),
  };
}

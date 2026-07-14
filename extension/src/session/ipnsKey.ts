import { ed25519 } from '@noble/curves/ed25519';
import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';
import { base36 } from 'multiformats/bases/base36';
import { CID } from 'multiformats/cid';
import { create as createDigest } from 'multiformats/hashes/digest';

import { hexToBytes } from '../util/bytes';

/**
 * Recalcula o nome IPNS (`k51...`) onde o Mobile publica o dead-drop
 * (13.9, fatia 2a: `mobile/lib/services/ipns_key_service.dart`) — a
 * extensão nunca guarda nem gera nenhum segredo aqui, só a metade pública da
 * mesma derivação determinística a partir do `sessionId` já embutido no QR.
 *
 * `HKDF_SALT`/`HKDF_INFO` precisam bater byte-a-byte com o lado Dart — é o
 * elo crítico entre os dois lados. Diferente do Dart (sem pacote maduro pra
 * CID/multihash/multibase, hand-rolled com vetor de teste), aqui o
 * `multiformats` (pacote oficial Protocol Labs) cobre tudo sem reimplementar
 * nada — só a derivação Ed25519/protobuf é código nosso.
 */
const HKDF_SALT = new TextEncoder().encode('TruthID Vault IPNS');
const HKDF_INFO = new TextEncoder().encode('dead-drop-key-v1');

const KEY_TYPE_ED25519 = 1;
const MULTICODEC_LIBP2P_KEY = 0x72;
const MULTIHASH_IDENTITY = 0x00;

// Protobuf `PublicKey` do libp2p (`crypto.proto`): `Type` (varint,
// Ed25519=1) + `Data` (bytes = chave pública, 32 bytes) — mesmo formato de
// `marshalPublicKeyProtobuf` no Dart.
function marshalPublicKeyProtobuf(publicKey: Uint8Array): Uint8Array {
  return new Uint8Array([0x08, KEY_TYPE_ED25519, 0x12, publicKey.length, ...publicKey]);
}

export function computeIpnsName(sessionIdHex: string): string {
  const sessionIdBytes = hexToBytes(sessionIdHex);
  const seed = hkdf(sha256, sessionIdBytes, HKDF_SALT, HKDF_INFO, 32);
  const publicKey = ed25519.getPublicKey(seed);
  const publicKeyProtobuf = marshalPublicKeyProtobuf(publicKey);

  const digest = createDigest(MULTIHASH_IDENTITY, publicKeyProtobuf);
  const cid = CID.createV1(MULTICODEC_LIBP2P_KEY, digest);
  return cid.toString(base36.encoder);
}

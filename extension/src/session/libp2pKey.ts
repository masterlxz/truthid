import { base36 } from 'multiformats/bases/base36';
import { CID } from 'multiformats/cid';
import { create as createDigest } from 'multiformats/hashes/digest';

/**
 * Matemática compartilhada entre `session/ipnsKey.ts` (pareamento de
 * leitura, Sessão 101) e `vaultEdit/deadDropIpnsKey.ts` (item 6 do backlog,
 * Sessão 109) — achado #9 (cleanup) do `/code-review` da Sessão 140: os dois
 * arquivos duplicavam byte a byte a montagem do protobuf de chave libp2p e a
 * codificação CID/multihash/base36. Só a derivação HKDF (salt/info,
 * domain-separada por namespace) e a orquestração continuam distintas em
 * cada arquivo — extrair isso junto misturaria os dois namespaces, que
 * precisam ficar sempre separados.
 *
 * Mirror do lado Dart, `mobile/lib/services/libp2p_key_util.dart` — aqui usa
 * o pacote oficial `multiformats` (Protocol Labs) pra CID/multihash/base36
 * em vez de hand-roll (o Dart não tem um pacote maduro equivalente).
 */
export const KEY_TYPE_ED25519 = 1;
export const MULTICODEC_LIBP2P_KEY = 0x72;
export const MULTIHASH_IDENTITY = 0x00;

// Mensagem protobuf de 2 campos (`Type` varint, `Data` bytes) do
// `crypto.proto` do libp2p — mesmo formato pra PrivateKey (`Data` =
// seed(32) || pubkey(32)) e PublicKey (`Data` = só a chave pública, 32
// bytes). Não é um encoder protobuf genérico: só cobre o caso concreto
// usado aqui (Type=Ed25519, Data sempre < 128 bytes, tag e length cabem
// num byte de varint cada).
export function marshalKeyProtobuf(data: Uint8Array): Uint8Array {
  if (data.length >= 128) {
    throw new Error('data too long for single-byte varint length');
  }
  return new Uint8Array([0x08, KEY_TYPE_ED25519, 0x12, data.length, ...data]);
}

/**
 * Nome IPNS (`k51...`) a partir do protobuf da chave pública: multihash
 * "identity" (código 0x00) → CIDv1 com codec `libp2p-key` (0x72) →
 * multibase base36-lower (prefixo `k`), formato que o Kubo usa hoje por
 * padrão pra nomes IPNS.
 */
export function computeIpnsNameFromPublicKeyProtobuf(publicKeyProtobuf: Uint8Array): string {
  const digest = createDigest(MULTIHASH_IDENTITY, publicKeyProtobuf);
  const cid = CID.createV1(MULTICODEC_LIBP2P_KEY, digest);
  return cid.toString(base36.encoder);
}

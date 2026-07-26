import { type Address, type Hex, encodeAbiParameters, keccak256 } from "viem";

interface BuildSessionDomainHashParams {
  chainId: number;
  sessionRegistryAddress: Address;
  hash: Hex;
}

/**
 * Computes the exact hash that `SessionRegistry.createSession` expects a
 * proof-of-possession signature over, a partir do fix C4 (replay
 * cross-chain, P26) — mirrors the Solidity side bit for bit:
 *
 *   keccak256(abi.encode(block.chainid, address(this), hash))
 *
 * This raw 32-byte domain hash is what gets sent for `personal_sign` (the
 * "\x19Ethereum Signed Message:\n32" prefix is applied by the device itself
 * when signing, and reapplied on-chain when verifying — never here). The
 * original `hash` (calldata do `createSession`) não muda — só o que é
 * assinado passa a incluir chainId + endereço do contrato.
 */
export function buildSessionDomainHash({
  chainId,
  sessionRegistryAddress,
  hash,
}: BuildSessionDomainHashParams): Hex {
  const encoded = encodeAbiParameters(
    [{ type: "uint256" }, { type: "address" }, { type: "bytes32" }],
    [BigInt(chainId), sessionRegistryAddress, hash],
  );

  return keccak256(encoded);
}

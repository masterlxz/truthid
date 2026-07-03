import { type Address, type Hex, encodeAbiParameters, keccak256 } from "viem";

interface BuildIdentityConsentHashParams {
  chainId: number;
  identityRegistryAddress: Address;
  username: string;
  controller: Address;
}

/**
 * Computes the exact hash that `IdentityRegistry.createIdentity` expects a
 * consent signature over (debt #17) — mirrors the Solidity side bit for bit:
 *
 *   keccak256(abi.encode(block.chainid, address(this), username, controller))
 *
 * This raw 32-byte hash is what gets sent to the Ledger via `personal_sign`
 * (the "\x19Ethereum Signed Message:\n32" prefix is applied by the device
 * itself when signing, and reapplied on-chain when verifying — never here).
 *
 * `encodeAbiParameters` (not packed encoding) is used because `username` is
 * a dynamic-length `string`, matching the Solidity function's own choice of
 * `abi.encode` over `abi.encodePacked` to avoid dynamic-type ambiguity.
 */
export function buildIdentityConsentHash({
  chainId,
  identityRegistryAddress,
  username,
  controller,
}: BuildIdentityConsentHashParams): Hex {
  const encoded = encodeAbiParameters(
    [{ type: "uint256" }, { type: "address" }, { type: "string" }, { type: "address" }],
    [BigInt(chainId), identityRegistryAddress, username, controller],
  );

  return keccak256(encoded);
}

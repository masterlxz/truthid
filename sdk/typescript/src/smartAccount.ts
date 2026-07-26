import {
  type Address,
  keccak256,
  encodeAbiParameters,
  encodePacked,
  concat,
  slice,
  getAddress,
} from "viem";

import {
  SMART_ACCOUNT_FACTORY_ADDRESSES,
  RECOVERY_MANAGER_ADDRESSES,
  DEVICE_REGISTRY_ADDRESSES,
  IDENTITY_REGISTRY_ADDRESSES,
  ENTRY_POINT_V07_ADDRESS,
} from "./contracts.js";
import { TRUTHID_ACCOUNT_CREATION_CODE } from "./truthidAccountBytecode.js";
import type { Network } from "./types.js";

// Predicts a TruthIDAccount's address via CREATE2 before it's deployed — pure
// local computation, no RPC call needed. Same algorithm as
// desktop/src/utils/computeSmartAccountAddress.ts, ported here so integrators
// don't need a TruthID server (or the desktop app) to know a user's smart
// account address ahead of time.
export function computeSmartAccountAddress(
  ledgerAddress: Address,
  network: Network,
  index: bigint = 0n,
): Address {
  const factoryAddress = SMART_ACCOUNT_FACTORY_ADDRESSES[network];

  // Must be encodePacked, not encodeAbiParameters — the contract uses
  // `abi.encodePacked(owner_, index)` (address with no left-pad, 20 bytes),
  // not `abi.encode` (address left-padded to 32 bytes). Using the wrong
  // encoding here produces a different salt than the factory computes
  // on-chain, yielding a controller address that never matches reality.
  const salt = keccak256(
    encodePacked(["address", "uint256"], [ledgerAddress, index]),
  );

  const constructorArgs = encodeAbiParameters(
    [
      { type: "address" },
      { type: "address" },
      { type: "address" },
      { type: "address" },
      { type: "address" },
    ],
    [
      ENTRY_POINT_V07_ADDRESS,
      DEVICE_REGISTRY_ADDRESSES[network],
      IDENTITY_REGISTRY_ADDRESSES[network],
      RECOVERY_MANAGER_ADDRESSES[network],
      ledgerAddress,
    ],
  );

  const initCode = concat([TRUTHID_ACCOUNT_CREATION_CODE, constructorArgs]);
  const initCodeHash = keccak256(initCode);

  const create2Input = concat(["0xff", factoryAddress, salt, initCodeHash]);
  const hash = keccak256(create2Input);

  return getAddress(slice(hash, 12));
}

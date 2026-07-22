import { describe, it, expect } from "vitest";
import { createPublicClient, http } from "viem";
import { base } from "viem/chains";
import {
  FACTORY_IMMUTABLES,
  TRUTHID_ACCOUNT_FACTORY_ADDRESS,
  ENTRY_POINT_V07,
} from "../../config/truthidAccount";

// ABI mínimo da factory — só os 4 getters de immutable do constructor.
const FACTORY_ABI = [
  {
    type: "function",
    name: "entryPoint",
    inputs: [],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "deviceRegistry",
    inputs: [],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "identityRegistry",
    inputs: [],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "recoveryManager",
    inputs: [],
    outputs: [{ type: "address" }],
    stateMutability: "view",
  },
] as const;

describe("truthidAccount factory immutables", () => {
  it("entryPoint hardcoded matches ERC-4337 constant", () => {
    const EXPECTED_ENTRY_POINT = "0x0000000071727De22E5E9d8BAf0edAc6f37da032" as const;
    expect(ENTRY_POINT_V07).toBe(EXPECTED_ENTRY_POINT);
  });

  it("FACTORY_IMMUTABLES match on-chain state on Base Mainnet", async () => {
    const publicClient = createPublicClient({
      chain: base,
      transport: http("https://mainnet.base.org"),
    });

    const [onChainEntryPoint, onChainDeviceRegistry, onChainIdentityRegistry, onChainRecoveryManager] =
      await Promise.all([
        publicClient.readContract({
          address: TRUTHID_ACCOUNT_FACTORY_ADDRESS,
          abi: FACTORY_ABI,
          functionName: "entryPoint",
        }),
        publicClient.readContract({
          address: TRUTHID_ACCOUNT_FACTORY_ADDRESS,
          abi: FACTORY_ABI,
          functionName: "deviceRegistry",
        }),
        publicClient.readContract({
          address: TRUTHID_ACCOUNT_FACTORY_ADDRESS,
          abi: FACTORY_ABI,
          functionName: "identityRegistry",
        }),
        publicClient.readContract({
          address: TRUTHID_ACCOUNT_FACTORY_ADDRESS,
          abi: FACTORY_ABI,
          functionName: "recoveryManager",
        }),
      ]);

    expect(onChainEntryPoint).toBe(FACTORY_IMMUTABLES.entryPoint);
    expect(onChainDeviceRegistry).toBe(FACTORY_IMMUTABLES.deviceRegistry);
    expect(onChainIdentityRegistry).toBe(FACTORY_IMMUTABLES.identityRegistry);
    expect(onChainRecoveryManager).toBe(FACTORY_IMMUTABLES.recoveryManager);
  }, 15_000);
});

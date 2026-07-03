import { describe, it, expect } from "vitest";
import { type Address, keccak256, toBytes, getAddress, slice } from "viem";
import { buildIdentityConsentHash } from "../buildIdentityConsentHash";

function makeAddr(label: string): Address {
  return getAddress(slice(keccak256(toBytes(label)), 12));
}

const REGISTRY = makeAddr("identityRegistry");
const CONTROLLER = makeAddr("controller");
const CHAIN_ID = 8453; // Base Mainnet

function build(overrides: Partial<Parameters<typeof buildIdentityConsentHash>[0]> = {}) {
  return buildIdentityConsentHash({
    chainId: CHAIN_ID,
    identityRegistryAddress: REGISTRY,
    username: "alice.id",
    controller: CONTROLLER,
    ...overrides,
  });
}

describe("buildIdentityConsentHash", () => {
  it("returns a well-formed 32-byte hash", () => {
    expect(build()).toMatch(/^0x[0-9a-fA-F]{64}$/);
  });

  it("is deterministic — same inputs always produce the same hash", () => {
    expect(build()).toBe(build());
  });

  it("changing chainId yields a different hash", () => {
    expect(build({ chainId: CHAIN_ID })).not.toBe(build({ chainId: 84532 })); // Base Sepolia
  });

  it("changing identityRegistryAddress yields a different hash", () => {
    expect(build()).not.toBe(build({ identityRegistryAddress: makeAddr("otherRegistry") }));
  });

  it("changing username yields a different hash", () => {
    expect(build()).not.toBe(build({ username: "bob.id" }));
  });

  it("changing controller yields a different hash", () => {
    expect(build()).not.toBe(build({ controller: makeAddr("otherController") }));
  });

  it("is reproducible across calls — no side effects", () => {
    const results = Array.from({ length: 10 }, () => build());
    results.forEach((r) => expect(r).toBe(results[0]));
  });
});

import { describe, it, expect } from "vitest";
import { type Address, type Hex, keccak256, toBytes, getAddress, slice } from "viem";
import { buildSessionDomainHash } from "../buildSessionDomainHash";

function makeAddr(label: string): Address {
  return getAddress(slice(keccak256(toBytes(label)), 12));
}

function makeHash(label: string): Hex {
  return keccak256(toBytes(label));
}

const SESSION_REGISTRY = makeAddr("sessionRegistry");
const SESSION_HASH = makeHash("session-nonce");
const CHAIN_ID = 8453; // Base Mainnet

function build(overrides: Partial<Parameters<typeof buildSessionDomainHash>[0]> = {}) {
  return buildSessionDomainHash({
    chainId: CHAIN_ID,
    sessionRegistryAddress: SESSION_REGISTRY,
    hash: SESSION_HASH,
    ...overrides,
  });
}

describe("buildSessionDomainHash", () => {
  it("returns a well-formed 32-byte hash", () => {
    expect(build()).toMatch(/^0x[0-9a-fA-F]{64}$/);
  });

  it("is deterministic — same inputs always produce the same hash", () => {
    expect(build()).toBe(build());
  });

  it("changing chainId yields a different hash (C4 cross-chain replay protection)", () => {
    expect(build({ chainId: CHAIN_ID })).not.toBe(build({ chainId: 84532 })); // Base Sepolia
  });

  it("changing sessionRegistryAddress yields a different hash", () => {
    expect(build()).not.toBe(build({ sessionRegistryAddress: makeAddr("otherRegistry") }));
  });

  it("changing hash yields a different hash", () => {
    expect(build()).not.toBe(build({ hash: makeHash("other-nonce") }));
  });

  it("is reproducible across calls — no side effects", () => {
    const results = Array.from({ length: 10 }, () => build());
    results.forEach((r) => expect(r).toBe(results[0]));
  });
});

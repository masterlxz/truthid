import { describe, it, expect } from "vitest";
import { getAddress } from "viem";
import { computeSmartAccountAddress } from "../smartAccount.js";

// Fixed cross-language parity vector — the exact same (ledgerAddress, network,
// index) is reused verbatim in sdk/python/tests/test_smart_account.py and
// sdk/ruby/spec/smart_account_spec.rb. All three MUST compute the same
// address; a mismatch means one of the three ports has an encoding bug
// (encodePacked vs abi.encode is an easy one to get wrong — it already caused
// a real bug once, see desktop's own test file).
const PARITY_LEDGER = "0x00000000000000000000000000000000000000ab" as const;
const PARITY_NETWORK = "base-sepolia" as const;
const PARITY_INDEX = 0n;

describe("computeSmartAccountAddress", () => {
  const ledger1 = "0x111111111111111111111111111111111111111a" as const;
  const ledger2 = "0x222222222222222222222222222222222222222b" as const;

  it("returns a valid, checksummed, non-zero address", () => {
    const addr = computeSmartAccountAddress(ledger1, "base-sepolia");
    expect(addr).toMatch(/^0x[0-9a-fA-F]{40}$/);
    expect(addr).not.toBe("0x0000000000000000000000000000000000000000");
    expect(getAddress(addr)).toBe(addr);
  });

  it("is deterministic — same inputs always produce the same address", () => {
    expect(computeSmartAccountAddress(ledger1, "base-sepolia")).toBe(
      computeSmartAccountAddress(ledger1, "base-sepolia"),
    );
  });

  it("different owners produce different addresses", () => {
    expect(computeSmartAccountAddress(ledger1, "base-sepolia")).not.toBe(
      computeSmartAccountAddress(ledger2, "base-sepolia"),
    );
  });

  it("different networks produce different addresses", () => {
    expect(computeSmartAccountAddress(ledger1, "base-sepolia")).not.toBe(
      computeSmartAccountAddress(ledger1, "base-mainnet"),
    );
  });

  it("different index for the same owner produces a different address", () => {
    const addr0 = computeSmartAccountAddress(ledger1, "base-sepolia", 0n);
    const addr1 = computeSmartAccountAddress(ledger1, "base-sepolia", 1n);
    expect(addr0).not.toBe(addr1);
  });

  it("is reproducible across repeated calls — no hidden side effects", () => {
    const results = Array.from({ length: 5 }, () =>
      computeSmartAccountAddress(ledger1, "base-sepolia"),
    );
    results.forEach((r) => expect(r).toBe(results[0]));
  });

  it("matches the fixed cross-language parity vector", () => {
    // Computed once with this exact TypeScript implementation — the
    // Python/Ruby ports must reproduce this same value byte-for-byte.
    const addr = computeSmartAccountAddress(
      PARITY_LEDGER,
      PARITY_NETWORK,
      PARITY_INDEX,
    );
    expect(addr).toBe("0xED83305810c42dEa66bA7C5c12BF61A7adC2356B");
  });
});

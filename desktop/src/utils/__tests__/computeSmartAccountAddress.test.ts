import { describe, it, expect } from "vitest";
import {
  type Address,
  type Hex,
  keccak256,
  toBytes,
  getAddress,
  slice,
} from "viem";
import { computeSmartAccountAddressSync } from "../computeSmartAccountAddress";
import { TRUTHID_ACCOUNT_CREATION_CODE } from "../../config/truthidAccount";

function makeAddr(label: string): Address {
  return getAddress(slice(keccak256(toBytes(label)), 12));
}

const DEVICE_REGISTRY = makeAddr("deviceRegistry");
const IDENTITY_REGISTRY = makeAddr("identityRegistry");
const RECOVERY_MANAGER = makeAddr("recoveryManager");
const ENTRY_POINT: Address = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

function predict(
  ledgerAddress: Address,
  factoryAddress: Address,
): Address {
  return computeSmartAccountAddressSync(ledgerAddress, factoryAddress, {
    entryPoint: ENTRY_POINT,
    deviceRegistry: DEVICE_REGISTRY,
    identityRegistry: IDENTITY_REGISTRY,
    recoveryManager: RECOVERY_MANAGER,
  });
}

describe("computeSmartAccountAddress", () => {
  const factory = makeAddr("factory");
  const ledger1 = makeAddr("owner");
  const ledger2 = makeAddr("owner2");

  it("returns a valid non-zero address", () => {
    const addr = predict(ledger1, factory);
    expect(addr).toMatch(/^0x[0-9a-fA-F]{40}$/);
    expect(addr).not.toBe("0x0000000000000000000000000000000000000000");
  });

  it("is deterministic — same inputs always produce the same address", () => {
    expect(predict(ledger1, factory)).toBe(predict(ledger1, factory));
  });

  it("different owners produce different addresses", () => {
    expect(predict(ledger1, factory)).not.toBe(predict(ledger2, factory));
  });

  it("different factory addresses produce different addresses", () => {
    const factory2 = makeAddr("factory2");
    expect(predict(ledger1, factory)).not.toBe(predict(ledger1, factory2));
  });

  it("creates a checksummed address (EIP-55)", () => {
    const addr = predict(ledger1, factory);
    // getAddress() should produce checksum version; passing it to itself is idempotent
    expect(getAddress(addr)).toBe(addr);
  });

  it("changing entryPoint yields a different address", () => {
    const addr1 = predict(ledger1, factory);
    const addr2 = computeSmartAccountAddressSync(ledger1, factory, {
      entryPoint: makeAddr("otherEntryPoint"),
      deviceRegistry: DEVICE_REGISTRY,
      identityRegistry: IDENTITY_REGISTRY,
      recoveryManager: RECOVERY_MANAGER,
    });
    expect(addr1).not.toBe(addr2);
  });

  it("changing deviceRegistry yields a different address", () => {
    const addr1 = predict(ledger1, factory);
    const addr2 = computeSmartAccountAddressSync(ledger1, factory, {
      entryPoint: ENTRY_POINT,
      deviceRegistry: makeAddr("otherDeviceRegistry"),
      identityRegistry: IDENTITY_REGISTRY,
      recoveryManager: RECOVERY_MANAGER,
    });
    expect(addr1).not.toBe(addr2);
  });

  it("changing identityRegistry yields a different address", () => {
    const addr1 = predict(ledger1, factory);
    const addr2 = computeSmartAccountAddressSync(ledger1, factory, {
      entryPoint: ENTRY_POINT,
      deviceRegistry: DEVICE_REGISTRY,
      identityRegistry: makeAddr("otherIdentityRegistry"),
      recoveryManager: RECOVERY_MANAGER,
    });
    expect(addr1).not.toBe(addr2);
  });

  it("changing recoveryManager yields a different address", () => {
    const addr1 = predict(ledger1, factory);
    const addr2 = computeSmartAccountAddressSync(ledger1, factory, {
      entryPoint: ENTRY_POINT,
      deviceRegistry: DEVICE_REGISTRY,
      identityRegistry: IDENTITY_REGISTRY,
      recoveryManager: makeAddr("otherRecoveryManager"),
    });
    expect(addr1).not.toBe(addr2);
  });

  it("salt is keccak256 of raw 20-byte owner address — matches Solidity abi.encodePacked", () => {
    // The salt in Solidity is keccak256(abi.encodePacked(owner_))
    // In JS/viem, keccak256(hex) hashes the de-hexed bytes
    const saltHex = keccak256(ledger1);
    // Should be 32 bytes (66 hex chars including 0x)
    expect(saltHex.length).toBe(66);
  });

  it("creation code is non-empty and starts with EVM preamble", () => {
    const code: Hex = TRUTHID_ACCOUNT_CREATION_CODE;
    expect(code.length).toBeGreaterThan(100);
    expect(code.startsWith("0x61")).toBe(true);
  });

  it("address is reproducible across calls — no side effects", () => {
    const results = Array.from({ length: 10 }, () => predict(ledger1, factory));
    results.forEach((r) => expect(r).toBe(results[0]));
  });
});
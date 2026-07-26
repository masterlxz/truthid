import { describe, it, expect, vi, beforeEach } from "vitest";

const readContractMock = vi.fn();
const recoverMessageAddressMock = vi.fn();

vi.mock("viem", async (importOriginal) => {
  const actual = await importOriginal<typeof import("viem")>();
  return {
    ...actual,
    createPublicClient: () => ({ readContract: readContractMock }),
    recoverMessageAddress: (...args: unknown[]) =>
      recoverMessageAddressMock(...args),
  };
});

const { TruthIDClient } = await import("../client.js");

const DEVICE_ADDRESS = "0x1111111111111111111111111111111111111a";

function makeChallenge(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    type: "challenge" as const,
    nonce: "nonce-1",
    issuedAt: Date.now(),
    origin: "https://example.com",
    ...overrides,
  };
}

describe("TruthIDClient", () => {
  let client: InstanceType<typeof TruthIDClient>;

  beforeEach(() => {
    readContractMock.mockReset();
    recoverMessageAddressMock.mockReset();
    client = new TruthIDClient({ network: "base-sepolia" });
  });

  describe("createChallenge", () => {
    it("returns the exact shape the mobile expects", () => {
      const challenge = client.createChallenge("https://example.com");
      expect(challenge.type).toBe("challenge");
      expect(challenge.origin).toBe("https://example.com");
      expect(typeof challenge.nonce).toBe("string");
      expect(typeof challenge.issuedAt).toBe("number");
    });

    it("generates a different nonce on every call", () => {
      const a = client.createChallenge("https://example.com");
      const b = client.createChallenge("https://example.com");
      expect(a.nonce).not.toBe(b.nonce);
    });
  });

  describe("verifyAuthResponse", () => {
    it("rejects when the user declined", async () => {
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: false,
          nonce: challenge.nonce,
          signature: "0x",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({
        valid: false,
        reason: "User rejected the login request",
      });
    });

    it("rejects an expired challenge", async () => {
      const challenge = makeChallenge({
        issuedAt: Date.now() - 60_000,
      });
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: challenge.nonce,
          signature: "0x",
          deviceAddress: DEVICE_ADDRESS,
        },
        ttlMs: 30_000,
      });
      expect(result).toEqual({ valid: false, reason: "Challenge expired" });
    });

    it("rejects a nonce mismatch", async () => {
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: "different-nonce",
          signature: "0x",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({ valid: false, reason: "Nonce mismatch" });
    });

    it("rejects a signature that fails to recover", async () => {
      recoverMessageAddressMock.mockRejectedValue(new Error("bad sig"));
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: challenge.nonce,
          signature: "0xbad",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({
        valid: false,
        reason: "Invalid signature format",
      });
    });

    it("rejects a signature that recovers to a different address", async () => {
      recoverMessageAddressMock.mockResolvedValue(
        "0x9999999999999999999999999999999999999999",
      );
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: challenge.nonce,
          signature: "0xgood",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({
        valid: false,
        reason: "Signature does not match device address",
      });
    });

    it("rejects a device that is not active", async () => {
      recoverMessageAddressMock.mockResolvedValue(DEVICE_ADDRESS);
      readContractMock.mockImplementation(async ({ functionName }) => {
        if (functionName === "isDeviceActive") return false;
        throw new Error(`unexpected call: ${functionName}`);
      });
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: challenge.nonce,
          signature: "0xgood",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({
        valid: false,
        reason: "Device is not active or has been revoked",
      });
    });

    it("succeeds and returns the identityId for a valid, active device", async () => {
      recoverMessageAddressMock.mockResolvedValue(DEVICE_ADDRESS);
      readContractMock.mockImplementation(async ({ functionName }) => {
        if (functionName === "isDeviceActive") return true;
        if (functionName === "getDevice") {
          return {
            identityId: 42n,
            pubKey: DEVICE_ADDRESS,
            label: "",
            addedAt: 0n,
            revoked: false,
            exists: true,
          };
        }
        throw new Error(`unexpected call: ${functionName}`);
      });
      const challenge = makeChallenge();
      const result = await client.verifyAuthResponse({
        challenge,
        response: {
          approved: true,
          nonce: challenge.nonce,
          signature: "0xgood",
          deviceAddress: DEVICE_ADDRESS,
        },
      });
      expect(result).toEqual({
        valid: true,
        identityId: 42n,
        deviceAddress: DEVICE_ADDRESS,
      });
    });
  });

  it("no longer exposes registerSession — the mobile registers sessions on-chain itself", () => {
    expect((client as unknown as Record<string, unknown>).registerSession).toBeUndefined();
  });
});

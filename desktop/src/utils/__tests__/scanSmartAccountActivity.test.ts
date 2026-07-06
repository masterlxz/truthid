import { describe, it, expect, vi } from "vitest";
import { scanSmartAccountActivity, type ScanClient } from "../scanSmartAccountActivity";

function makeMockClient(overrides: Partial<ScanClient> = {}): ScanClient {
  return {
    getContractEvents: vi.fn().mockResolvedValue([]),
    getTransactionReceipt: vi.fn().mockResolvedValue({ gasUsed: 21_000n, effectiveGasPrice: 1_000_000_000n }),
    getBlock: vi.fn().mockResolvedValue({ timestamp: 1_700_000_000n }),
    ...overrides,
  } as unknown as ScanClient;
}

const HASH_A = "0xaaaa000000000000000000000000000000000000000000000000000000000a" as const;
const HASH_B = "0xbbbb000000000000000000000000000000000000000000000000000000000b" as const;

describe("scanSmartAccountActivity", () => {
  it("walks the range forward in fixed-size chunks, including a partial final chunk", async () => {
    const client = makeMockClient();

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 4500n });

    const calls = vi.mocked(client.getContractEvents).mock.calls as unknown as [{ fromBlock: bigint; toBlock: bigint }][];
    const ranges = [...new Set(calls.map(([c]) => `${c.fromBlock}-${c.toBlock}`))];

    expect(ranges).toEqual(["100-2099", "2100-4099", "4100-4500"]);
  });

  it("scans all 6 event sources, including VaultUpdated", async () => {
    const client = makeMockClient();

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    const eventNames = vi
      .mocked(client.getContractEvents)
      .mock.calls.map(([args]) => (args as { eventName: string }).eventName);

    expect([...eventNames].sort()).toEqual(
      ["AllSessionsRevoked", "DeviceRegistered", "DeviceRevoked", "SessionCreated", "SessionRevoked", "VaultUpdated"].sort(),
    );
  });

  it("fetches the receipt for a tx hash only once even when 2 logs share it", async () => {
    const client = makeMockClient({
      getContractEvents: vi.fn(async ({ eventName }: { eventName: string }) =>
        eventName === "DeviceRegistered"
          ? [
              { transactionHash: HASH_A, blockNumber: 150n, logIndex: 0 },
              { transactionHash: HASH_A, blockNumber: 150n, logIndex: 1 },
            ]
          : [],
      ) as unknown as ScanClient["getContractEvents"],
    });

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    expect(client.getTransactionReceipt).toHaveBeenCalledTimes(1);
    expect(client.getTransactionReceipt).toHaveBeenCalledWith({ hash: HASH_A });
  });

  it("fetches the block only once even when 2 logs share the same block number", async () => {
    const client = makeMockClient({
      getContractEvents: vi.fn(async ({ eventName }: { eventName: string }) =>
        eventName === "SessionCreated"
          ? [
              { transactionHash: HASH_A, blockNumber: 150n, logIndex: 0 },
              { transactionHash: HASH_B, blockNumber: 150n, logIndex: 1 },
            ]
          : [],
      ) as unknown as ScanClient["getContractEvents"],
    });

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    expect(client.getBlock).toHaveBeenCalledTimes(1);
    expect(client.getBlock).toHaveBeenCalledWith({ blockNumber: 150n });
  });

  it("maps a log into a SmartAccountActivity with costWei = gasUsed * effectiveGasPrice", async () => {
    const client = makeMockClient({
      getContractEvents: vi.fn(async ({ eventName }: { eventName: string }) =>
        eventName === "SessionCreated"
          ? [{ transactionHash: HASH_A, blockNumber: 500n, logIndex: 2 }]
          : [],
      ) as unknown as ScanClient["getContractEvents"],
      getTransactionReceipt: vi.fn().mockResolvedValue({ gasUsed: 50_000n, effectiveGasPrice: 2_000_000_000n }),
      getBlock: vi.fn().mockResolvedValue({ timestamp: 1_720_000_000n }),
    });

    const result = await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 600n });

    expect(result).toEqual([
      {
        type: "session_created",
        hash: HASH_A,
        blockNumber: 500n,
        logIndex: 2,
        timestamp: 1_720_000_000,
        costWei: 100_000_000_000_000n,
      },
    ]);
  });

  it("invokes onChunkScanned once per chunk with a growing, sorted array", async () => {
    const client = makeMockClient({
      getContractEvents: vi.fn(async ({ eventName, fromBlock }: { eventName: string; fromBlock: bigint }) => {
        if (eventName === "SessionCreated" && fromBlock === 100n) {
          return [{ transactionHash: HASH_A, blockNumber: 150n, logIndex: 0 }];
        }
        if (eventName === "DeviceRegistered" && fromBlock === 2100n) {
          return [{ transactionHash: HASH_B, blockNumber: 2150n, logIndex: 0 }];
        }
        return [];
      }) as unknown as ScanClient["getContractEvents"],
    });

    const onChunkScanned = vi.fn();
    await scanSmartAccountActivity(client, {
      identityId: 1n,
      fromBlock: 100n,
      toBlock: 3000n,
      onChunkScanned,
    });

    // Range [100, 3000] split into chunks [100,2099] and [2100,3000].
    expect(onChunkScanned).toHaveBeenCalledTimes(2);

    const [firstActivities] = onChunkScanned.mock.calls[0] as [{ blockNumber: bigint }[], unknown];
    const [secondActivities] = onChunkScanned.mock.calls[1] as [{ blockNumber: bigint }[], unknown];

    expect(firstActivities.map((a) => a.blockNumber)).toEqual([150n]);
    expect(secondActivities.map((a) => a.blockNumber)).toEqual([150n, 2150n]);
  });
});

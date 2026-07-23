import { describe, it, expect, vi } from "vitest";
import { toEventSelector } from "viem";
import { scanSmartAccountActivity, type ScanClient } from "../scanSmartAccountActivity";
import {
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ABI,
  VAULT_REGISTRY_ABI,
} from "../../config/contracts";

// Topic0 real de cada evento — calculado a partir das mesmas ABIs que o
// scanner usa, pra montar respostas de eth_getLogs realistas nos mocks
// (Sessão 122/123: as 6 fontes agora vêm de uma única chamada combinada,
// então cada log precisa carregar seu próprio `topics[0]` pra o scanner
// saber classificar o tipo).
const TOPIC = {
  DeviceRegistered: toEventSelector(DEVICE_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "DeviceRegistered")!),
  DeviceRevoked: toEventSelector(DEVICE_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "DeviceRevoked")!),
  SessionCreated: toEventSelector(SESSION_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "SessionCreated")!),
  SessionRevoked: toEventSelector(SESSION_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "SessionRevoked")!),
  AllSessionsRevoked: toEventSelector(SESSION_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "AllSessionsRevoked")!),
  VaultUpdated: toEventSelector(VAULT_REGISTRY_ABI.find((i) => i.type === "event" && i.name === "VaultUpdated")!),
};

function rawLog(eventName: keyof typeof TOPIC, txHash: `0x${string}`, blockNumber: bigint, logIndex: number) {
  return {
    topics: [TOPIC[eventName]],
    transactionHash: txHash,
    blockNumber: `0x${blockNumber.toString(16)}`,
    logIndex: `0x${logIndex.toString(16)}`,
  };
}

function makeMockClient(overrides: Partial<ScanClient> = {}): ScanClient {
  return {
    request: vi.fn().mockResolvedValue([]),
    getTransactionReceipt: vi.fn().mockResolvedValue({ gasUsed: 21_000n, effectiveGasPrice: 1_000_000_000n }),
    getBlock: vi.fn().mockResolvedValue({ number: 150n, timestamp: 1_700_000_000n }),
    ...overrides,
  } as unknown as ScanClient;
}

const HASH_A = "0xaaaa000000000000000000000000000000000000000000000000000000000a" as const;
const HASH_B = "0xbbbb000000000000000000000000000000000000000000000000000000000b" as const;

describe("scanSmartAccountActivity", () => {
  it("walks the range forward in fixed-size chunks, including a partial final chunk", async () => {
    const client = makeMockClient();

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 4500n });

    const calls = vi.mocked(client.request).mock.calls as unknown as [{ params: [{ fromBlock: string; toBlock: string }] }][];
    const ranges = [...new Set(calls.map(([c]) => `${BigInt(c.params[0].fromBlock)}-${BigInt(c.params[0].toBlock)}`))];

    expect(ranges).toEqual(["100-2099", "2100-4099", "4100-4500"]);
  });

  it("faz 1 única chamada eth_getLogs por chunk combinando os 6 endereços/topic0s", async () => {
    const client = makeMockClient();

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    expect(client.request).toHaveBeenCalledTimes(1);
    const [{ method, params }] = vi.mocked(client.request).mock.calls[0] as unknown as [{ method: string; params: [{ address: string[]; topics: [string[], string] }] }];

    expect(method).toBe("eth_getLogs");
    expect(new Set(params[0].address).size).toBe(3); // DeviceRegistry + SessionRegistry + VaultRegistry
    expect(params[0].topics[0]).toHaveLength(6); // 6 tipos de evento combinados via OR
  });

  it("fetches the receipt for a tx hash only once even when 2 logs share it", async () => {
    const client = makeMockClient({
      request: vi.fn().mockResolvedValue([
        rawLog("DeviceRegistered", HASH_A, 150n, 0),
        rawLog("DeviceRegistered", HASH_A, 150n, 1),
      ]) as unknown as ScanClient["request"],
    });

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    expect(client.getTransactionReceipt).toHaveBeenCalledTimes(1);
    expect(client.getTransactionReceipt).toHaveBeenCalledWith({ hash: HASH_A });
  });

  it("fetches the block only once even when 2 logs share the same block number", async () => {
    const client = makeMockClient({
      request: vi.fn().mockResolvedValue([
        rawLog("SessionCreated", HASH_A, 150n, 0),
        rawLog("SessionCreated", HASH_B, 150n, 1),
      ]) as unknown as ScanClient["request"],
    });

    await scanSmartAccountActivity(client, { identityId: 1n, fromBlock: 100n, toBlock: 200n });

    expect(client.getBlock).toHaveBeenCalledTimes(1);
    expect(client.getBlock).toHaveBeenCalledWith({ blockNumber: 150n });
  });

  it("maps a log into a SmartAccountActivity with costWei = gasUsed * effectiveGasPrice", async () => {
    const client = makeMockClient({
      request: vi.fn().mockResolvedValue([rawLog("SessionCreated", HASH_A, 500n, 2)]) as unknown as ScanClient["request"],
      getTransactionReceipt: vi.fn().mockResolvedValue({ gasUsed: 50_000n, effectiveGasPrice: 2_000_000_000n }),
      getBlock: vi.fn().mockResolvedValue({ number: 500n, timestamp: 1_720_000_000n }),
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
      request: vi.fn(async (args: unknown) => {
        const { params } = args as { params: [{ fromBlock: string }] };
        const fromBlock = BigInt(params[0].fromBlock);
        if (fromBlock === 100n) return [rawLog("SessionCreated", HASH_A, 150n, 0)];
        if (fromBlock === 2100n) return [rawLog("DeviceRegistered", HASH_B, 2150n, 0)];
        return [];
      }) as unknown as ScanClient["request"],
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

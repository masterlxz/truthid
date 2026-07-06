import type { Abi, Address, Hash, PublicClient } from "viem";
import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ADDRESS,
  SESSION_REGISTRY_ABI,
  VAULT_REGISTRY_ADDRESS,
  VAULT_REGISTRY_ABI,
} from "../config/contracts";
import type { SmartAccountActivity, SmartAccountActivityType } from "../types";

// Mesmo valor já validado contra RPCs públicos da Base (limite de "query
// exceeds max block range" visto em mobile/lib/services/blockchain_service.dart).
const CHUNK_SIZE = 2000n;

type EventSource = {
  address: Address;
  abi: Abi;
  eventName: string;
  type: SmartAccountActivityType;
};

// Todos os 6 eventos indexam `identityId`, então o filtro `args: { identityId }`
// já deixa o RPC descartar eventos de outras identidades — o utilitário nunca
// busca-e-descarta nada.
const EVENT_SOURCES: EventSource[] = [
  { address: DEVICE_REGISTRY_ADDRESS, abi: DEVICE_REGISTRY_ABI as Abi, eventName: "DeviceRegistered", type: "device_registered" },
  { address: DEVICE_REGISTRY_ADDRESS, abi: DEVICE_REGISTRY_ABI as Abi, eventName: "DeviceRevoked", type: "device_revoked" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "SessionCreated", type: "session_created" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "SessionRevoked", type: "session_revoked" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "AllSessionsRevoked", type: "session_revoked_all" },
  { address: VAULT_REGISTRY_ADDRESS, abi: VAULT_REGISTRY_ABI as Abi, eventName: "VaultUpdated", type: "vault_updated" },
];

export type ScanClient = Pick<PublicClient, "getContractEvents" | "getTransactionReceipt" | "getBlock">;

export type ScanProgress = { scannedTo: bigint; latest: bigint };

export type ScanParams = {
  identityId: bigint;
  fromBlock: bigint;
  toBlock: bigint;
  onChunkScanned?: (activitiesSoFar: SmartAccountActivity[], progress: ScanProgress) => void;
};

function sortActivities(activities: SmartAccountActivity[]): void {
  activities.sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) return a.blockNumber < b.blockNumber ? -1 : 1;
    return a.logIndex - b.logIndex;
  });
}

/**
 * Varre os eventos de sessão/device/vault de uma identidade, do bloco `fromBlock`
 * até `toBlock` (inclusive), em chunks de `CHUNK_SIZE` blocos, pra frente.
 *
 * Escala esperada é dezenas de operações por identidade, então receipts/blocks
 * são buscados sequencialmente (não em paralelo) — mais simples de deduplicar
 * corretamente por hash/bloco sem lidar com corrida entre buscas concorrentes.
 */
export async function scanSmartAccountActivity(
  client: ScanClient,
  params: ScanParams,
): Promise<SmartAccountActivity[]> {
  const { identityId, fromBlock, toBlock, onChunkScanned } = params;

  const receiptCache = new Map<Hash, { gasUsed: bigint; effectiveGasPrice: bigint }>();
  const blockTimestampCache = new Map<bigint, bigint>();
  const activities: SmartAccountActivity[] = [];

  let chunkFrom = fromBlock;
  while (chunkFrom <= toBlock) {
    const chunkTo = chunkFrom + CHUNK_SIZE - 1n > toBlock ? toBlock : chunkFrom + CHUNK_SIZE - 1n;

    const logsPerSource = await Promise.all(
      EVENT_SOURCES.map(async (source) => {
        const logs = await client.getContractEvents({
          address: source.address,
          abi: source.abi,
          eventName: source.eventName,
          args: { identityId },
          fromBlock: chunkFrom,
          toBlock: chunkTo,
        } as Parameters<ScanClient["getContractEvents"]>[0]);
        return logs.map((log) => ({ log, type: source.type }));
      }),
    );

    for (const { log, type } of logsPerSource.flat()) {
      const hash = log.transactionHash as Hash;
      const blockNumber = log.blockNumber as bigint;
      const logIndex = log.logIndex as number;

      let receipt = receiptCache.get(hash);
      if (!receipt) {
        const fetched = await client.getTransactionReceipt({ hash });
        receipt = { gasUsed: fetched.gasUsed, effectiveGasPrice: fetched.effectiveGasPrice };
        receiptCache.set(hash, receipt);
      }

      let timestamp = blockTimestampCache.get(blockNumber);
      if (timestamp === undefined) {
        const block = await client.getBlock({ blockNumber });
        timestamp = block.timestamp;
        blockTimestampCache.set(blockNumber, timestamp);
      }

      activities.push({
        type,
        hash,
        blockNumber,
        logIndex,
        timestamp: Number(timestamp),
        costWei: receipt.gasUsed * receipt.effectiveGasPrice,
      });
    }

    sortActivities(activities);
    onChunkScanned?.(activities.slice(), { scannedTo: chunkTo, latest: toBlock });

    chunkFrom = chunkTo + 1n;
  }

  return activities;
}

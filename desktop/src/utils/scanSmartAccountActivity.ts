import { toEventSelector } from "viem";
import type { Abi, AbiEvent, Address, Hash, PublicClient } from "viem";
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

// Todos os 6 eventos indexam `identityId`, então o filtro por topic já deixa
// o RPC descartar eventos de outras identidades — o utilitário nunca
// busca-e-descarta nada.
const EVENT_SOURCES: EventSource[] = [
  { address: DEVICE_REGISTRY_ADDRESS, abi: DEVICE_REGISTRY_ABI as Abi, eventName: "DeviceRegistered", type: "device_registered" },
  { address: DEVICE_REGISTRY_ADDRESS, abi: DEVICE_REGISTRY_ABI as Abi, eventName: "DeviceRevoked", type: "device_revoked" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "SessionCreated", type: "session_created" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "SessionRevoked", type: "session_revoked" },
  { address: SESSION_REGISTRY_ADDRESS, abi: SESSION_REGISTRY_ABI as Abi, eventName: "AllSessionsRevoked", type: "session_revoked_all" },
  { address: VAULT_REGISTRY_ADDRESS, abi: VAULT_REGISTRY_ABI as Abi, eventName: "VaultUpdated", type: "vault_updated" },
];

function findAbiEvent(abi: Abi, eventName: string): AbiEvent {
  const found = abi.find((item): item is AbiEvent => item.type === "event" && item.name === eventName);
  if (!found) throw new Error(`Event ${eventName} not found in ABI`);
  return found;
}

// Sessão 122/123: mesmo fix aplicado no Mobile (blockchain_service.dart /
// smart_account_activity_scanner.dart). Um scan de histórico completo cruza
// ~250 chunks; buscar cada fonte separado (6 chamadas eth_getLogs paralelas
// por chunk) soma ~1500 chamadas contra RPCs públicos gratuitos, estourando
// rate limit. `address` e `topics[0]` no eth_getLogs aceitam lista (o nó faz
// OR dentro da posição), e o topic0 de cada evento é o hash da própria
// assinatura (único por tipo) — dá pra combinar as 6 fontes numa chamada só
// por chunk sem contaminação cruzada. `getContractEvents`/`getLogs` do viem
// não dão esse controle quando combinam múltiplos eventos (descartam o
// filtro por `args` nesse caso — ver node_modules/viem/actions/public/getLogs.ts),
// por isso o request cru via `client.request` em vez da action de conveniência.
const ADDRESSES: Address[] = Array.from(new Set(EVENT_SOURCES.map((s) => s.address)));
const TOPIC0_BY_INDEX: Hash[] = EVENT_SOURCES.map((s) => toEventSelector(findAbiEvent(s.abi, s.eventName)));
const TYPE_BY_TOPIC0 = new Map<string, SmartAccountActivityType>(
  EVENT_SOURCES.map((s, i) => [TOPIC0_BY_INDEX[i].toLowerCase(), s.type]),
);

export type ScanClient = Pick<PublicClient, "request" | "getTransactionReceipt" | "getBlock">;

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

type RawLog = {
  topics: Hash[];
  transactionHash: Hash;
  blockNumber: Hash;
  logIndex: Hash;
};

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

  const idTopic = `0x${identityId.toString(16).padStart(64, "0")}` as Hash;
  const receiptCache = new Map<Hash, { gasUsed: bigint; effectiveGasPrice: bigint }>();
  const blockTimestampCache = new Map<bigint, bigint>();
  const activities: SmartAccountActivity[] = [];

  let chunkFrom = fromBlock;
  while (chunkFrom <= toBlock) {
    const chunkTo = chunkFrom + CHUNK_SIZE - 1n > toBlock ? toBlock : chunkFrom + CHUNK_SIZE - 1n;

    const rawLogs = (await client.request({
      method: "eth_getLogs",
      params: [
        {
          address: ADDRESSES,
          topics: [TOPIC0_BY_INDEX, idTopic],
          fromBlock: `0x${chunkFrom.toString(16)}`,
          toBlock: `0x${chunkTo.toString(16)}`,
        },
      ],
    } as Parameters<ScanClient["request"]>[0])) as unknown as RawLog[];

    // Busca receipts e blocos únicos em paralelo em vez de sequencial
    // dentro do loop — cada chunk pode ter várias transações/blocos que
    // compartilham o mesmo receipt ou timestamp (bug #30).
    const uniqueHashes = [...new Set(rawLogs.map((l) => l.transactionHash))];
    const uniqueBlockNumbers = [
      ...new Set(rawLogs.map((l) => BigInt(l.blockNumber))),
    ];
    const [receiptResults, blockResults] = await Promise.all([
      Promise.all(
        uniqueHashes
          .filter((h) => !receiptCache.has(h))
          .map((hash) =>
            client
              .getTransactionReceipt({ hash })
              .then((r) => ({ hash, gasUsed: r.gasUsed, effectiveGasPrice: r.effectiveGasPrice })),
          ),
      ),
      Promise.all(
        uniqueBlockNumbers
          .filter((b) => !blockTimestampCache.has(b))
          .map((blockNumber) =>
            client
              .getBlock({ blockNumber })
              .then((b) => ({ number: b.number, timestamp: b.timestamp })),
          ),
      ),
    ]);
    for (const { hash, gasUsed, effectiveGasPrice } of receiptResults) {
      receiptCache.set(hash, { gasUsed, effectiveGasPrice });
    }
    for (const { number, timestamp } of blockResults) {
      if (number !== null) blockTimestampCache.set(number, timestamp);
    }

    for (const log of rawLogs) {
      const type = TYPE_BY_TOPIC0.get(log.topics[0].toLowerCase());
      if (!type) continue; // topic0 fora da lista pedida, não deveria acontecer

      const hash = log.transactionHash;
      const blockNumber = BigInt(log.blockNumber);
      const logIndex = Number(log.logIndex);

      const receipt = receiptCache.get(hash)!;
      const timestamp = blockTimestampCache.get(blockNumber)!;

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

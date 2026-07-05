import { useCallback, useEffect, useRef, useState } from "react";
import { usePublicClient } from "wagmi";
import {
  DEVICE_REGISTRY_DEPLOY_BLOCK,
  SESSION_REGISTRY_DEPLOY_BLOCK,
} from "../config/contracts";
import { scanSmartAccountActivity, type ScanProgress } from "../utils/scanSmartAccountActivity";
import type { SmartAccountActivity } from "../types";

const DEPLOY_BLOCK =
  DEVICE_REGISTRY_DEPLOY_BLOCK < SESSION_REGISTRY_DEPLOY_BLOCK
    ? DEVICE_REGISTRY_DEPLOY_BLOCK
    : SESSION_REGISTRY_DEPLOY_BLOCK;

type SerializedActivity = Omit<SmartAccountActivity, "blockNumber" | "costWei"> & {
  blockNumber: string;
  costWei: string;
};

type CachedState = {
  lastScannedBlock: string;
  activities: SerializedActivity[];
};

function cacheKey(identityId: bigint): string {
  return `truthid.activity.${identityId}`;
}

function serialize(activities: SmartAccountActivity[]): SerializedActivity[] {
  return activities.map((a) => ({
    ...a,
    blockNumber: a.blockNumber.toString(),
    costWei: a.costWei.toString(),
  }));
}

function deserialize(activities: SerializedActivity[]): SmartAccountActivity[] {
  return activities.map((a) => ({
    ...a,
    blockNumber: BigInt(a.blockNumber),
    costWei: BigInt(a.costWei),
  }));
}

function readCache(identityId: bigint): { lastScannedBlock: bigint; activities: SmartAccountActivity[] } | null {
  try {
    const raw = localStorage.getItem(cacheKey(identityId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedState;
    return {
      lastScannedBlock: BigInt(parsed.lastScannedBlock),
      activities: deserialize(parsed.activities),
    };
  } catch {
    // JSON malformado/de outra versão — tudo é rederivável da chain, então
    // cair pra um scan completo é seguro.
    return null;
  }
}

function writeCache(identityId: bigint, lastScannedBlock: bigint, activities: SmartAccountActivity[]): void {
  try {
    const payload: CachedState = {
      lastScannedBlock: lastScannedBlock.toString(),
      activities: serialize(activities),
    };
    localStorage.setItem(cacheKey(identityId), JSON.stringify(payload));
  } catch {
    // localStorage indisponível/cheio — o cache é só uma otimização de
    // performance, a próxima visita simplesmente reescaneia mais devagar.
  }
}

function clearCache(identityId: bigint): void {
  try {
    localStorage.removeItem(cacheKey(identityId));
  } catch {
    // ignore
  }
}

export function useSmartAccountActivity(identityId: bigint | undefined): {
  activities: SmartAccountActivity[];
  isScanning: boolean;
  progress: ScanProgress | null;
  error: Error | null;
  rescan: () => void;
} {
  const publicClient = usePublicClient();
  const [activities, setActivities] = useState<SmartAccountActivity[]>([]);
  const [isScanning, setIsScanning] = useState(false);
  const [progress, setProgress] = useState<ScanProgress | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [rescanToken, setRescanToken] = useState(0);
  const scanInFlight = useRef(false);

  const rescan = useCallback(() => {
    if (identityId !== undefined) clearCache(identityId);
    setActivities([]);
    setProgress(null);
    setRescanToken((t) => t + 1);
  }, [identityId]);

  useEffect(() => {
    if (identityId === undefined || !publicClient) return;

    const cached = readCache(identityId);
    if (cached) setActivities(cached.activities);

    if (scanInFlight.current) return;
    scanInFlight.current = true;
    setError(null);
    setIsScanning(true);

    let cancelled = false;
    const baseActivities = cached?.activities ?? [];

    (async () => {
      try {
        const latest = await publicClient.getBlockNumber();
        const fromBlock =
          cached && cached.lastScannedBlock < latest ? cached.lastScannedBlock + 1n : DEPLOY_BLOCK;

        if (fromBlock > latest) return; // já escaneado até o bloco mais recente

        const scanned = await scanSmartAccountActivity(publicClient, {
          identityId,
          fromBlock,
          toBlock: latest,
          onChunkScanned: (chunkActivities, prog) => {
            if (cancelled) return;
            setActivities([...baseActivities, ...chunkActivities]);
            setProgress(prog);
          },
        });

        if (cancelled) return;
        const merged = [...baseActivities, ...scanned];
        setActivities(merged);
        writeCache(identityId, latest, merged);
      } catch (err) {
        if (!cancelled) setError(err as Error);
      } finally {
        if (!cancelled) setIsScanning(false);
        scanInFlight.current = false;
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [identityId, publicClient, rescanToken]);

  return { activities, isScanning, progress, error, rescan };
}

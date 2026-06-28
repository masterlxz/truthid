import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
} from "../config/contracts";
import type { DeviceInfo } from "../types";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { DeviceList } from "./DeviceList";
import { PairDevice } from "./PairDevice";
import { DesktopDevice } from "./DesktopDevice";

export function ManageDevices() {
  const { username, identityId } = useIdentity();
  const { isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();
  const queryClient = useQueryClient();

  // ── Leitura 1: buscar lista de pubkeys dos devices desta identidade ───────
  const { data: devicePubKeys, refetch: refetchDevices } = useReadContract({
    address: DEVICE_REGISTRY_ADDRESS,
    abi: DEVICE_REGISTRY_ABI,
    functionName: "getDevicesByIdentity",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  // ── Leitura 2: buscar detalhes de cada device em paralelo ─────────────────
  const { data: deviceResults, refetch: refetchDeviceDetails } = useReadContracts({
    contracts: (devicePubKeys ?? []).map((pk) => ({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice" as const,
      args: [pk] as const,
    })),
    query: { enabled: !!devicePubKeys && devicePubKeys.length > 0 },
  });

  const devices = (deviceResults ?? [])
    .map((r) => r.result)
    .filter(Boolean) as DeviceInfo[];

  // ── Revogar device ────────────────────────────────────────────────────────
  const [revokingPubKey, setRevokingPubKey] = useState<string | null>(null);

  const {
    writeContract: sendRevoke,
    data: revokeTxHash,
    isPending: isRevokePending,
  } = useWriteContract();

  const { isLoading: isRevokeConfirming, isSuccess: isRevokeSuccess } =
    useWaitForTransactionReceipt({ hash: revokeTxHash });

  function handleRevoke(pubKey: string) {
    if (!isConnected) { openConnectModal(); return; }
    setRevokingPubKey(pubKey);
    sendRevoke({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "revokeDevice",
      args: [pubKey as `0x${string}`],
    });
  }

  useEffect(() => {
    if (isRevokeSuccess) {
      setRevokingPubKey(null);
      queryClient.invalidateQueries();
      // Wait for the RPC node to index the new block before refetching
      setTimeout(() => { refetchDevices(); refetchDeviceDetails(); }, 3000);
    }
  }, [isRevokeSuccess]);

  const handleDeviceRegistered = () => {
    refetchDevices();
    refetchDeviceDetails();
  };

  return (
    <div>
      <h2>@{username}</h2>

      <DeviceList
        devices={devices}
        revokingPubKey={revokingPubKey}
        isRevokePending={isRevokePending}
        isRevokeConfirming={isRevokeConfirming}
        onRevoke={handleRevoke}
      />

      <hr />

      <PairDevice onDeviceRegistered={handleDeviceRegistered} />

      <DesktopDevice onRegistered={handleDeviceRegistered} />
    </div>
  );
}

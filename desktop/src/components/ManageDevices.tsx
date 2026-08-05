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
  TRUTHID_ACCOUNT_ABI,
} from "../config/contracts";
import type { DeviceInfo } from "../types";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { buildAccountCalls } from "../utils/buildAccountCalls";
import { buildRotationBatch } from "../services/rotateVaultKeyOnRevoke";
import { DeviceList } from "./DeviceList";
import { PairDevice } from "./PairDevice";
import { DesktopDevice } from "./DesktopDevice";

export function ManageDevices() {
  const { username, identityId, smartAccountAddress } = useIdentity();
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
    if (!smartAccountAddress) return;
    if (rotationPhase !== "idle") return; // evita duas rotações correndo em paralelo
    setRevokingPubKey(pubKey);

    // Mesma razão da 14.8 em PairDevice/DesktopDevice: msg.sender do
    // DeviceRegistry precisa ser a smart account, não o Ledger — e
    // aproveitamos o lote pra também tirar o device da lista de signers
    // da própria smart account.
    const { dest, value, func } = buildAccountCalls([
      {
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "revokeDevice",
        args: [pubKey as `0x${string}`],
      },
      {
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "removeDevice",
        args: [pubKey as `0x${string}`],
      },
    ]);
    sendRevoke({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "executeBatch",
      args: [dest, value, func],
    });
  }

  // ── Rotação de DEK, disparada logo depois da revogação confirmar ──────────
  // Fecha o gap onde um device revogado continuava com a cópia da chave do
  // vault que já tinha decifrado antes — gera uma DEK nova, republica o
  // vault sob ela, e redistribui só pros devices que restaram ativos.
  const [rotationPhase, setRotationPhase] = useState<"idle" | "rotating" | "confirming">("idle");
  const [rotationError, setRotationError] = useState<string | null>(null);
  const [rotationWarning, setRotationWarning] = useState<string | null>(null);

  const { writeContract: sendRotation, data: rotationTxHash } = useWriteContract();
  const { isSuccess: isRotationSuccess } = useWaitForTransactionReceipt({ hash: rotationTxHash });

  useEffect(() => {
    if (!isRevokeSuccess || !revokingPubKey || !smartAccountAddress) return;

    // `devices` ainda reflete o estado antes do refetch (que só roda depois
    // de um delay) — filtra localmente pra excluir o device que acabou de
    // ser revogado, mesmo com a leitura on-chain ainda desatualizada.
    const remaining = devices
      .filter(
        (d) =>
          !d.revoked && d.pubKey.toLowerCase() !== revokingPubKey.toLowerCase()
      )
      .map((d) => d.pubKey);

    const justRevoked = revokingPubKey;
    setRevokingPubKey(null);
    queryClient.invalidateQueries();
    setTimeout(() => { refetchDevices(); refetchDeviceDetails(); }, 3000);

    setRotationPhase("rotating");
    setRotationError(null);
    setRotationWarning(null);
    buildRotationBatch(remaining as `0x${string}`[])
      .then(({ dest, value, func, providersFailed }) => {
        if (providersFailed.length > 0) {
          setRotationWarning(
            `Redundância parcial ao republicar o vault: falhou em ${providersFailed.join(", ")}.`
          );
        }
        setRotationPhase("confirming");
        sendRotation({
          address: smartAccountAddress,
          abi: TRUTHID_ACCOUNT_ABI,
          functionName: "executeBatch",
          args: [dest, value, func],
        });
      })
      .catch((e) => {
        setRotationError(
          `Falha ao rotacionar a chave do vault depois de revogar ${justRevoked}: ${String(e)}`
        );
        setRotationPhase("idle");
      });
  }, [isRevokeSuccess]);

  useEffect(() => {
    if (isRotationSuccess) {
      setRotationPhase("idle");
      queryClient.invalidateQueries();
    }
  }, [isRotationSuccess]);

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

      {rotationPhase === "rotating" && (
        <p className="muted">Re-cifrando o vault com uma chave nova...</p>
      )}
      {rotationPhase === "confirming" && (
        <p className="muted">Confirmar na carteira e distribuir a chave nova pros devices restantes...</p>
      )}
      {rotationWarning && (
        <p style={{ color: "#d9a441", marginBottom: 0, marginTop: "0.5rem", fontSize: "0.9em" }}>
          ⚠ {rotationWarning}
        </p>
      )}
      {rotationError && <p className="error-text">{rotationError}</p>}

      <hr />

      <PairDevice onDeviceRegistered={handleDeviceRegistered} />

      <DesktopDevice onRegistered={handleDeviceRegistered} />
    </div>
  );
}

import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import type { Address } from "viem";
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
import { buildAccountCalls } from "../utils/buildAccountCalls";
import type { DeviceInfo } from "../types";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { buildRotationBatch, type RemainingDevice } from "../services/rotateVaultKeyOnRevoke";
import { DeviceList } from "./DeviceList";
import { PairDevice } from "./PairDevice";
import { DesktopDevice } from "./DesktopDevice";
import { RedistributeVaultKey } from "./RedistributeVaultKey";

export function ManageDevices() {
  const { t } = useTranslation();
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

  // ── Leitura 3: `authorizedDevices` é estado próprio da smart account
  // (`TruthIDAccount`), separado do registro global no `DeviceRegistry`
  // acima — um redeploy em cascata (débito #52, ver
  // `migrateDevices()`/CASCADE.md) migra os registros do DeviceRegistry pra
  // uma smart account nova, mas nunca chamou `addDevice()` nela: um device
  // pode aparecer "ativo" no DeviceRegistry e mesmo assim não conseguir
  // assinar nenhum UserOp pra essa conta (achado real, P52, Sessão 205 —
  // `authorizedDevices` batia `false` pros 7 devices migrados). Detectado
  // aqui pra oferecer a reautorização em lote abaixo.
  const { data: authorizedResults, refetch: refetchAuthorized } = useReadContracts({
    contracts: devices.map((d) => ({
      address: smartAccountAddress ?? undefined,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "authorizedDevices" as const,
      args: [d.pubKey as `0x${string}`] as const,
    })),
    query: { enabled: !!smartAccountAddress && devices.length > 0 },
  });

  const devicesNeedingReauth = devices.filter((d, i) => {
    if (d.revoked) return false;
    const authorized = authorizedResults?.[i]?.result;
    return authorized === false;
  });

  const {
    writeContract: sendReauthorize,
    data: reauthorizeTxHash,
    isPending: isReauthorizePending,
    isError: isReauthorizeError,
    error: reauthorizeError,
  } = useWriteContract();

  const { isLoading: isReauthorizeConfirming, isSuccess: isReauthorizeSuccess } =
    useWaitForTransactionReceipt({ hash: reauthorizeTxHash });

  useEffect(() => {
    if (!isReauthorizeSuccess) return;
    queryClient.invalidateQueries();
    setTimeout(() => refetchAuthorized(), 3000);
  }, [isReauthorizeSuccess]);

  function handleReauthorize() {
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress || devicesNeedingReauth.length === 0) return;

    // Um só `executeBatch`, uma só confirmação na Ledger — sem re-pareamento
    // físico dos outros devices, o pubkey de cada um já é conhecido on-chain
    // (`getDevicesByIdentity`), só falta o `addDevice()` que a migração
    // pulou.
    const { dest, value, func } = buildAccountCalls(
      devicesNeedingReauth.map((d) => ({
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "addDevice",
        args: [d.pubKey as `0x${string}`],
      }))
    );
    sendReauthorize({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "executeBatch",
      args: [dest, value, func],
    });
  }

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
    if (rotationPhase !== "idle" || pendingRemaining !== null) return; // evita duas rotações correndo em paralelo
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

  // ── Rotação de DEK, oferecida logo depois da revogação confirmar ──────────
  // Fecha o gap onde um device revogado continuava com a cópia da chave do
  // vault que já tinha decifrado antes — gera uma DEK nova, republica o
  // vault sob ela, e redistribui só pros devices que restaram ativos.
  //
  // Diferente da versão anterior, NÃO dispara sozinha: `DeviceRegistry` só
  // guarda o endereço de cada device, nunca a chave pública crua que o
  // ECIES precisa (ver nota em `rotateVaultKeyOnRevoke.ts`) — sem ela, a
  // cifra pra cada device restante sempre falharia, e a versão antiga já
  // tinha commitado a rotação local (keyring + vault.enc) antes desse erro
  // acontecer, deixando o Desktop dessincronizado do que estava publicado
  // (achado real, P54/Sessão 205). Agora quem revoga precisa colar a chave
  // pública crua de cada device restante antes de confirmar — mesmo dado
  // que `PairDevice.tsx` já pede no pareamento inicial.
  const [pendingRemaining, setPendingRemaining] = useState<Address[] | null>(null);
  const [rawPubkeys, setRawPubkeys] = useState<Record<string, string>>({});
  const [rotationPhase, setRotationPhase] = useState<"idle" | "rotating" | "confirming">("idle");
  const [rotationError, setRotationError] = useState<string | null>(null);

  const { writeContract: sendRotation, data: rotationTxHash } = useWriteContract();
  const { isSuccess: isRotationSuccess } = useWaitForTransactionReceipt({ hash: rotationTxHash });

  useEffect(() => {
    if (!isRevokeSuccess || !revokingPubKey) return;

    // `devices` ainda reflete o estado antes do refetch (que só roda depois
    // de um delay) — filtra localmente pra excluir o device que acabou de
    // ser revogado, mesmo com a leitura on-chain ainda desatualizada.
    const remaining = devices
      .filter((d) => !d.revoked && d.pubKey.toLowerCase() !== revokingPubKey.toLowerCase())
      .map((d) => d.pubKey as Address);

    setRevokingPubKey(null);
    queryClient.invalidateQueries();
    setTimeout(() => { refetchDevices(); refetchDeviceDetails(); }, 3000);

    if (remaining.length > 0) {
      setPendingRemaining(remaining);
      setRawPubkeys({});
      setRotationError(null);
    }
  }, [isRevokeSuccess]);

  function handleConfirmRotation() {
    if (!pendingRemaining || !smartAccountAddress) return;
    const remainingActiveDevices: RemainingDevice[] = pendingRemaining.map((pubKey) => ({
      pubKey,
      rawPubkeyHex: rawPubkeys[pubKey] ?? "",
    }));
    if (remainingActiveDevices.some((d) => !d.rawPubkeyHex)) return;

    setRotationPhase("rotating");
    setRotationError(null);
    buildRotationBatch(remainingActiveDevices)
      .then(({ dest, value, func }) => {
        setRotationPhase("confirming");
        sendRotation({
          address: smartAccountAddress,
          abi: TRUTHID_ACCOUNT_ABI,
          functionName: "executeBatch",
          args: [dest, value, func],
        });
      })
      .catch((e) => {
        setRotationError(t("manageDevices.rotationBanner.rotationFailed", { error: String(e) }));
        setRotationPhase("idle");
      });
  }

  useEffect(() => {
    if (isRotationSuccess) {
      setRotationPhase("idle");
      setPendingRemaining(null);
      setRawPubkeys({});
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

      {devicesNeedingReauth.length > 0 && (
        <div className="card" style={{ marginBottom: "1rem", borderColor: "var(--warning, #c99a2e)" }}>
          <p style={{ marginTop: 0 }}>
            {t("manageDevices.reauthBanner.body", { count: devicesNeedingReauth.length })}
          </p>
          <button onClick={handleReauthorize} disabled={isReauthorizePending || isReauthorizeConfirming}>
            {isReauthorizePending
              ? t("manageDevices.reauthBanner.confirmingWallet")
              : isReauthorizeConfirming
              ? t("manageDevices.reauthBanner.waitingNetwork")
              : t("manageDevices.reauthBanner.confirmButton", { count: devicesNeedingReauth.length })}
          </button>
          {isReauthorizeError && (
            <p className="error-text" style={{ marginBottom: 0 }}>
              {reauthorizeError?.message?.split("\n")[0]}
            </p>
          )}
        </div>
      )}

      <DeviceList
        devices={devices}
        revokingPubKey={revokingPubKey}
        isRevokePending={isRevokePending}
        isRevokeConfirming={isRevokeConfirming}
        onRevoke={handleRevoke}
      />

      {pendingRemaining && pendingRemaining.length > 0 && (
        <div className="card" style={{ marginBottom: "1rem", borderColor: "var(--warning, #c99a2e)" }}>
          <p style={{ marginTop: 0 }}>
            {t("manageDevices.rotationBanner.body", { count: pendingRemaining.length })}
          </p>
          {pendingRemaining.map((pubKey) => {
            const device = devices.find((d) => d.pubKey.toLowerCase() === pubKey.toLowerCase());
            return (
              <div className="field" key={pubKey}>
                <label>{device?.label ?? pubKey}</label>
                <input
                  value={rawPubkeys[pubKey] ?? ""}
                  onChange={(e) =>
                    setRawPubkeys((prev) => ({ ...prev, [pubKey]: e.target.value.trim() }))
                  }
                  placeholder={t("manageDevices.rotationBanner.pubkeyPlaceholder")}
                  disabled={rotationPhase !== "idle"}
                  style={{ fontFamily: "monospace", fontSize: "0.8rem" }}
                />
              </div>
            );
          })}
          <div className="actions-row">
            <button
              onClick={handleConfirmRotation}
              disabled={
                rotationPhase !== "idle" ||
                pendingRemaining.some((pk) => !rawPubkeys[pk])
              }
            >
              {rotationPhase === "rotating"
                ? t("manageDevices.rotationBanner.rotatingButton")
                : rotationPhase === "confirming"
                ? t("manageDevices.rotationBanner.confirmingWallet")
                : t("manageDevices.rotationBanner.confirmButton")}
            </button>
            <button
              onClick={() => { setPendingRemaining(null); setRawPubkeys({}); }}
              disabled={rotationPhase !== "idle"}
            >
              {t("manageDevices.rotationBanner.postponeButton")}
            </button>
          </div>
          {rotationError && <p className="error-text">{rotationError}</p>}
        </div>
      )}

      <hr />

      <PairDevice onDeviceRegistered={handleDeviceRegistered} />

      <DesktopDevice onRegistered={handleDeviceRegistered} />

      <RedistributeVaultKey devices={devices} />
    </div>
  );
}

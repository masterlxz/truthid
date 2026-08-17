import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ADDRESS,
  SESSION_REGISTRY_ABI,
} from "../config/contracts";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { formatDateTime } from "../i18n/formatDate";

export function ActiveSessions() {
  const { t, i18n } = useTranslation();
  const { username, identityId } = useIdentity();
  const { isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();

  // ── Leitura 1: lista de hashes de sessão desta identidade ─────────────────
  const { data: sessionHashes, refetch: refetchHashes } = useReadContract({
    address: SESSION_REGISTRY_ADDRESS,
    abi: SESSION_REGISTRY_ABI,
    functionName: "getSessionsByIdentity",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  // ── Leitura 2: detalhes de cada sessão em paralelo ────────────────────────
  const { data: sessionResults, refetch: refetchSessions } = useReadContracts({
    contracts: (sessionHashes ?? []).map((hash) => ({
      address: SESSION_REGISTRY_ADDRESS,
      abi: SESSION_REGISTRY_ABI,
      functionName: "getSession" as const,
      args: [hash] as const,
    })),
    query: { enabled: !!sessionHashes && sessionHashes.length > 0 },
  });

  const sessions = (sessionResults ?? [])
    .map((r, i) =>
      r.result ? { hash: sessionHashes![i], ...r.result } : null
    )
    .filter(Boolean) as SessionWithHash[];

  // ── Leitura 3: label de cada device em paralelo ───────────────────────────
  // Queremos mostrar "iPhone 15 Pro" em vez de "0x1a2b…" para cada sessão.
  // Buscamos o device de cada sessão usando o devicePubKey.
  const devicePubKeys = sessions.map((s) => s.devicePubKey);

  const { data: deviceResults } = useReadContracts({
    contracts: devicePubKeys.map((pk) => ({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice" as const,
      args: [pk] as const,
    })),
    query: { enabled: devicePubKeys.length > 0 },
  });

  // Monta um mapa pubKey → label para consulta rápida na renderização
  const deviceLabels: Record<string, string> = {};
  (deviceResults ?? []).forEach((r, i) => {
    if (r.result) deviceLabels[devicePubKeys[i]] = r.result.label;
  });

  // ── Revogar sessão individual ─────────────────────────────────────────────
  const [revokingHash, setRevokingHash] = useState<string | null>(null);

  const {
    writeContract: sendRevokeOne,
    data: revokeOneTxHash,
    isPending: isRevokeOnePending,
  } = useWriteContract();

  const { isLoading: isRevokeOneConfirming, isSuccess: isRevokeOneSuccess } =
    useWaitForTransactionReceipt({ hash: revokeOneTxHash });

  function handleRevokeOne(hash: `0x${string}`) {
    if (!isConnected) { openConnectModal(); return; }
    setRevokingHash(hash);
    sendRevokeOne({
      address: SESSION_REGISTRY_ADDRESS,
      abi: SESSION_REGISTRY_ABI,
      functionName: "revokeSession",
      args: [hash],
    });
  }

  useEffect(() => {
    if (isRevokeOneSuccess) {
      setRevokingHash(null);
      refetchHashes();
      refetchSessions();
    }
  }, [isRevokeOneSuccess]);

  // ── Revogar todas as sessões ──────────────────────────────────────────────
  const {
    writeContract: sendRevokeAll,
    data: revokeAllTxHash,
    isPending: isRevokeAllPending,
  } = useWriteContract();

  const { isLoading: isRevokeAllConfirming, isSuccess: isRevokeAllSuccess } =
    useWaitForTransactionReceipt({ hash: revokeAllTxHash });

  const [revokeAllDone, setRevokeAllDone] = useState(false);

  function handleRevokeAll() {
    if (!isConnected) { openConnectModal(); return; }
    sendRevokeAll({
      address: SESSION_REGISTRY_ADDRESS,
      abi: SESSION_REGISTRY_ABI,
      functionName: "revokeAllSessions",
      args: [],
    });
  }

  useEffect(() => {
    if (isRevokeAllSuccess) {
      setRevokeAllDone(true);
      refetchHashes();
      refetchSessions();
    }
  }, [isRevokeAllSuccess]);

  useEffect(() => {
    setRevokeAllDone(false);
  }, [sessionResults]);

  // ── Renderização ──────────────────────────────────────────────────────────

  const activeSessions = sessions.filter((s) => !s.revoked);
  const isBusy = isRevokeAllPending || isRevokeAllConfirming;

  return (
    <div>
      <h2>@{username}</h2>
      <h3>{t("activeSessions.title")}</h3>

      {sessions.length === 0 && (
        <p className="muted">{t("activeSessions.empty")}</p>
      )}

      {sessions.map((session) => {
        const isBeingRevoked = revokingHash === session.hash;
        const isRevoked =
          session.revoked ||
          (revokeAllDone && !session.revoked);
        const createdAt = formatDateTime(Number(session.createdAt), i18n.language);
        const deviceLabel =
          deviceLabels[session.devicePubKey] ??
          `${session.devicePubKey.slice(0, 8)}…`;
        const hashShort = `${session.hash.slice(0, 10)}…${session.hash.slice(-6)}`;

        return (
          <div key={session.hash} className={`card${isRevoked ? " is-revoked" : ""}`}>
            <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
              <code className="address">{hashShort}</code>
              <span className={`status-badge ${isRevoked ? "status-badge--revoked" : "status-badge--active"}`}>
                {isRevoked ? t("activeSessions.status.revoked") : t("activeSessions.status.active")}
              </span>
            </div>
            <span className="muted">{t("activeSessions.device", { label: deviceLabel })}</span>
            <span className="muted"> · {t("activeSessions.createdAt", { date: createdAt })}</span>
            {!isRevoked && (
              <div className="actions-row">
                <button
                  onClick={() => handleRevokeOne(session.hash as `0x${string}`)}
                  disabled={
                    isRevokeOnePending || isRevokeOneConfirming || isBusy
                  }
                >
                  {isBeingRevoked && isRevokeOnePending
                    ? t("activeSessions.actions.confirmInWallet")
                    : isBeingRevoked && isRevokeOneConfirming
                    ? t("activeSessions.actions.waitingForNetwork")
                    : t("activeSessions.actions.revoke")}
                </button>
              </div>
            )}
          </div>
        );
      })}

      {activeSessions.length > 0 && (
        <div className="actions-row">
          <button onClick={handleRevokeAll} disabled={isBusy}>
            {isRevokeAllPending
              ? t("activeSessions.actions.confirmInWallet")
              : isRevokeAllConfirming
              ? t("activeSessions.actions.waitingForNetwork")
              : t("activeSessions.actions.revokeAll", { count: activeSessions.length })}
          </button>
        </div>
      )}
    </div>
  );
}

type SessionWithHash = {
  hash: `0x${string}`;
  identityId: bigint;
  devicePubKey: string;
  createdAt: bigint;
  revoked: boolean;
  exists: boolean;
};

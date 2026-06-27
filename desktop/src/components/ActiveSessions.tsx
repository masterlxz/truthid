import { useEffect, useState } from "react";
import {
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ADDRESS,
  SESSION_REGISTRY_ABI,
} from "../config/contracts";

export function ActiveSessions({ username }: { username: string }) {
  // ── Leitura 1: identityId a partir do username ────────────────────────────
  const { data: identity } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getIdentity",
    args: [username],
  });

  const identityId = identity?.id;

  // ── Leitura 2: lista de hashes de sessão desta identidade ─────────────────
  const { data: sessionHashes, refetch: refetchHashes } = useReadContract({
    address: SESSION_REGISTRY_ADDRESS,
    abi: SESSION_REGISTRY_ABI,
    functionName: "getSessionsByIdentity",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  // ── Leitura 3: detalhes de cada sessão em paralelo ────────────────────────
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

  // ── Leitura 4: label de cada device em paralelo ───────────────────────────
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

  function handleRevokeAll() {
    sendRevokeAll({
      address: SESSION_REGISTRY_ADDRESS,
      abi: SESSION_REGISTRY_ABI,
      functionName: "revokeAllSessions",
      args: [],
    });
  }

  useEffect(() => {
    if (isRevokeAllSuccess) {
      refetchHashes();
      refetchSessions();
    }
  }, [isRevokeAllSuccess]);

  // ── Renderização ──────────────────────────────────────────────────────────

  const activeSessions = sessions.filter((s) => !s.revoked);
  const isBusy = isRevokeAllPending || isRevokeAllConfirming;

  return (
    <div>
      <h2>@{username}</h2>
      <h3>Sessões ativas</h3>

      {sessions.length === 0 && (
        <p>Nenhuma sessão registrada. As sessões aparecem aqui quando você faz login em sites usando TruthID.</p>
      )}

      {sessions.map((session) => {
        const isBeingRevoked = revokingHash === session.hash;
        const isRevoked =
          session.revoked ||
          (isRevokeAllSuccess && !session.revoked);
        const createdAt = new Date(
          Number(session.createdAt) * 1000
        ).toLocaleString("pt-BR");
        const deviceLabel =
          deviceLabels[session.devicePubKey] ??
          `${session.devicePubKey.slice(0, 8)}…`;
        const hashShort = `${session.hash.slice(0, 10)}…${session.hash.slice(-6)}`;

        return (
          <div
            key={session.hash}
            style={{
              marginBottom: "1rem",
              opacity: isRevoked ? 0.5 : 1,
            }}
          >
            <strong style={{ fontFamily: "monospace" }}>{hashShort}</strong>
            <span> — {isRevoked ? "❌ Revogada" : "✅ Ativa"}</span>
            <br />
            <small>Dispositivo: {deviceLabel}</small>
            <small> · Criada em {createdAt}</small>
            <br />
            {!isRevoked && (
              <button
                onClick={() => handleRevokeOne(session.hash as `0x${string}`)}
                disabled={
                  isRevokeOnePending || isRevokeOneConfirming || isBusy
                }
              >
                {isBeingRevoked && isRevokeOnePending
                  ? "Confirme no MetaMask..."
                  : isBeingRevoked && isRevokeOneConfirming
                  ? "Aguardando rede..."
                  : "Revogar"}
              </button>
            )}
          </div>
        );
      })}

      {activeSessions.length > 0 && (
        <>
          <hr />
          <button onClick={handleRevokeAll} disabled={isBusy}>
            {isRevokeAllPending
              ? "Confirme no MetaMask..."
              : isRevokeAllConfirming
              ? "Aguardando rede..."
              : `Revogar todas (${activeSessions.length})`}
          </button>
        </>
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

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { isAddress, type Address } from "viem";
import {
  RECOVERY_MANAGER_ADDRESS,
  RECOVERY_MANAGER_ABI,
  TRUTHID_ACCOUNT_ABI,
} from "../config/contracts";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { buildAccountCalls } from "../utils/buildAccountCalls";

function formatAddress(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function timeRemaining(proposedAt: bigint): string {
  const TIMELOCK_SECS = 7n * 86400n;
  const now = BigInt(Math.floor(Date.now() / 1000));
  const deadline = proposedAt + TIMELOCK_SECS;
  if (now >= deadline) return "Ready to execute";
  const diff = Number(deadline - now);
  const d = Math.floor(diff / 86400);
  const h = Math.floor((diff % 86400) / 3600);
  const m = Math.floor((diff % 3600) / 60);
  return `${d}d ${h}h ${m}m remaining`;
}

type ProposalStatus = "none" | "active" | "executed" | "cancelled";

export function GuardianManagement() {
  const { username, smartAccountAddress } = useIdentity();
  const { address: connectedAddress, isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();
  const queryClient = useQueryClient();

  // ── Reads ──────────────────────────────────────────────────────────────────

  const { data: guardianConfig, refetch: refetchConfig } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "getGuardianConfig",
    args: [username],
    query: { enabled: !!username },
  });

  const guardians = useMemo(() => guardianConfig?.guardians ?? [], [guardianConfig]);
  const threshold = guardianConfig?.threshold ?? 0n;
  const isConfigured = guardians.length > 0;

  const { data: proposal, refetch: refetchProposal } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "getProposal",
    args: [username],
    query: { enabled: !!username },
  });

  const proposalStatus: ProposalStatus = useMemo(() => {
    if (!proposal || !proposal.exists) return "none";
    if (proposal.executed) return "executed";
    if (proposal.cancelled) return "cancelled";
    return "active";
  }, [proposal]);

  const isGuardian = useMemo(
    () => !!connectedAddress && guardians.some((g) => g.toLowerCase() === connectedAddress.toLowerCase()),
    [connectedAddress, guardians],
  );

  const { data: hasApproved } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "hasGuardianApproved",
    args: proposalStatus === "active" ? [username, connectedAddress as Address] : undefined,
    query: { enabled: proposalStatus === "active" && !!connectedAddress && isGuardian },
  });

  const { data: timelock } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "TIMELOCK",
    args: [],
  });

  // ── Configure guardians ────────────────────────────────────────────────────

  const [showConfigForm, setShowConfigForm] = useState(false);
  const [guardianInputs, setGuardianInputs] = useState<string[]>([""]);
  const [thresholdInput, setThresholdInput] = useState(3);
  const [configError, setConfigError] = useState<string | null>(null);

  const {
    writeContract: sendConfig,
    data: configTxHash,
    isPending: isConfigPending,
    isError: isConfigError,
    error: configWriteError,
    reset: resetConfig,
  } = useWriteContract();

  const { isLoading: isConfigConfirming, isSuccess: isConfigSuccess } =
    useWaitForTransactionReceipt({ hash: configTxHash });

  useEffect(() => {
    if (isConfigSuccess) {
      setShowConfigForm(false);
      queryClient.invalidateQueries();
      setTimeout(() => { refetchConfig(); refetchProposal(); }, 3000);
    }
  }, [isConfigSuccess]);

  function handleConfigure() {
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress) return;
    setConfigError(null);

    const validAddresses = guardianInputs
      .map((a) => a.trim())
      .filter((a) => a.length > 0);

    if (validAddresses.length === 0) {
      setConfigError("Add at least one guardian address");
      return;
    }
    if (validAddresses.some((a) => !isAddress(a))) {
      setConfigError("One or more addresses are invalid");
      return;
    }
    if (thresholdInput < 1 || thresholdInput > validAddresses.length) {
      setConfigError("Threshold must be between 1 and the number of guardians");
      return;
    }

    const { dest, value, func } = buildAccountCalls([
      {
        address: RECOVERY_MANAGER_ADDRESS,
        abi: RECOVERY_MANAGER_ABI,
        functionName: "configureGuardians",
        args: [username, validAddresses as Address[], BigInt(thresholdInput)],
      },
    ]);
    sendConfig({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "execute",
      args: [dest[0], value[0], func[0]],
    });
  }

  function addGuardianField() {
    setGuardianInputs([...guardianInputs, ""]);
  }

  function updateGuardianField(idx: number, val: string) {
    const next = [...guardianInputs];
    next[idx] = val;
    setGuardianInputs(next);
  }

  function removeGuardianField(idx: number) {
    if (guardianInputs.length <= 1) return;
    setGuardianInputs(guardianInputs.filter((_, i) => i !== idx));
  }

  // ── Propose recovery ───────────────────────────────────────────────────────

  const [newController, setNewController] = useState("");
  const [proposeError, setProposeError] = useState<string | null>(null);

  const {
    writeContract: sendPropose,
    data: proposeTxHash,
    isPending: isProposePending,
    isError: isProposeError,
    error: proposeWriteError,
  } = useWriteContract();

  const { isLoading: isProposeConfirming, isSuccess: isProposeSuccess } =
    useWaitForTransactionReceipt({ hash: proposeTxHash });

  useEffect(() => {
    if (isProposeSuccess) {
      setNewController("");
      queryClient.invalidateQueries();
      setTimeout(refetchProposal, 3000);
    }
  }, [isProposeSuccess]);

  function handlePropose() {
    if (!isConnected) { openConnectModal(); return; }
    setProposeError(null);
    if (!isAddress(newController.trim())) {
      setProposeError("Invalid controller address");
      return;
    }
    sendPropose({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "proposeRecovery",
      args: [username, newController.trim() as Address],
    });
  }

  // ── Approve recovery ───────────────────────────────────────────────────────

  const {
    writeContract: sendApprove,
    data: approveTxHash,
    isPending: isApprovePending,
    isError: isApproveError,
    error: approveWriteError,
  } = useWriteContract();

  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  useEffect(() => {
    if (isApproveSuccess) {
      queryClient.invalidateQueries();
      setTimeout(() => { refetchProposal(); }, 3000);
    }
  }, [isApproveSuccess]);

  function handleApprove() {
    if (!isConnected) { openConnectModal(); return; }
    sendApprove({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "approveRecovery",
      args: [username],
    });
  }

  // ── Execute recovery ───────────────────────────────────────────────────────

  const {
    writeContract: sendExecute,
    data: executeTxHash,
    isPending: isExecutePending,
    isError: isExecuteError,
    error: executeWriteError,
  } = useWriteContract();

  const { isLoading: isExecuteConfirming, isSuccess: isExecuteSuccess } =
    useWaitForTransactionReceipt({ hash: executeTxHash });

  useEffect(() => {
    if (isExecuteSuccess) {
      queryClient.invalidateQueries();
      setTimeout(() => { refetchProposal(); refetchConfig(); }, 3000);
    }
  }, [isExecuteSuccess]);

  function handleExecute() {
    if (!isConnected) { openConnectModal(); return; }
    sendExecute({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "executeRecovery",
      args: [username],
    });
  }

  // ── Cancel recovery ────────────────────────────────────────────────────────

  const {
    writeContract: sendCancel,
    data: cancelTxHash,
    isPending: isCancelPending,
    isError: isCancelError,
    error: cancelWriteError,
  } = useWriteContract();

  const { isLoading: isCancelConfirming, isSuccess: isCancelSuccess } =
    useWaitForTransactionReceipt({ hash: cancelTxHash });

  useEffect(() => {
    if (isCancelSuccess) {
      queryClient.invalidateQueries();
      setTimeout(() => { refetchProposal(); }, 3000);
    }
  }, [isCancelSuccess]);

  function handleCancel() {
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress) return;
    const { dest, value, func } = buildAccountCalls([
      {
        address: RECOVERY_MANAGER_ADDRESS,
        abi: RECOVERY_MANAGER_ABI,
        functionName: "cancelRecovery",
        args: [username],
      },
    ]);
    sendCancel({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "execute",
      args: [dest[0], value[0], func[0]],
    });
  }

  // ── Act as guardian (for another identity) ─────────────────────────────────
  // P39: as seções acima sempre operam sobre `username` (a identidade de quem
  // está conectado — `App.tsx` deriva de getUsernameByController do próprio
  // smartAccountAddress). Um guardião de verdade é OUTRA pessoa, então
  // precisa buscar explicitamente o username de quem ele está guardando —
  // sem isso, Propose/Approve nunca eram alcançáveis na prática.

  const [guardianTargetInput, setGuardianTargetInput] = useState("");
  const [guardianTarget, setGuardianTarget] = useState<string | null>(null);

  const { data: targetGuardianConfig } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "getGuardianConfig",
    args: guardianTarget ? [guardianTarget] : undefined,
    query: { enabled: !!guardianTarget },
  });
  const targetGuardians = useMemo(() => targetGuardianConfig?.guardians ?? [], [targetGuardianConfig]);
  const targetThreshold = targetGuardianConfig?.threshold ?? 0n;
  const targetIsGuardian = useMemo(
    () => !!connectedAddress && targetGuardians.some((g) => g.toLowerCase() === connectedAddress.toLowerCase()),
    [connectedAddress, targetGuardians],
  );

  const { data: targetProposal, refetch: refetchTargetProposal } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "getProposal",
    args: guardianTarget ? [guardianTarget] : undefined,
    query: { enabled: !!guardianTarget },
  });
  const targetProposalStatus: ProposalStatus = useMemo(() => {
    if (!targetProposal || !targetProposal.exists) return "none";
    if (targetProposal.executed) return "executed";
    if (targetProposal.cancelled) return "cancelled";
    return "active";
  }, [targetProposal]);

  const { data: targetHasApproved } = useReadContract({
    address: RECOVERY_MANAGER_ADDRESS,
    abi: RECOVERY_MANAGER_ABI,
    functionName: "hasGuardianApproved",
    args: targetProposalStatus === "active" && guardianTarget ? [guardianTarget, connectedAddress as Address] : undefined,
    query: { enabled: targetProposalStatus === "active" && !!connectedAddress && targetIsGuardian && !!guardianTarget },
  });

  const [targetNewController, setTargetNewController] = useState("");
  const [targetProposeError, setTargetProposeError] = useState<string | null>(null);

  const {
    writeContract: sendTargetPropose,
    data: targetProposeTxHash,
    isPending: isTargetProposePending,
    isError: isTargetProposeError,
    error: targetProposeWriteError,
  } = useWriteContract();

  const { isLoading: isTargetProposeConfirming, isSuccess: isTargetProposeSuccess } =
    useWaitForTransactionReceipt({ hash: targetProposeTxHash });

  useEffect(() => {
    if (isTargetProposeSuccess) {
      setTargetNewController("");
      queryClient.invalidateQueries();
      setTimeout(refetchTargetProposal, 3000);
    }
  }, [isTargetProposeSuccess]);

  function handleTargetPropose() {
    if (!isConnected) { openConnectModal(); return; }
    if (!guardianTarget) return;
    setTargetProposeError(null);
    if (!isAddress(targetNewController.trim())) {
      setTargetProposeError("Invalid controller address");
      return;
    }
    sendTargetPropose({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "proposeRecovery",
      args: [guardianTarget, targetNewController.trim() as Address],
    });
  }

  const {
    writeContract: sendTargetApprove,
    data: targetApproveTxHash,
    isPending: isTargetApprovePending,
    isError: isTargetApproveError,
    error: targetApproveWriteError,
  } = useWriteContract();

  const { isLoading: isTargetApproveConfirming, isSuccess: isTargetApproveSuccess } =
    useWaitForTransactionReceipt({ hash: targetApproveTxHash });

  useEffect(() => {
    if (isTargetApproveSuccess) {
      queryClient.invalidateQueries();
      setTimeout(refetchTargetProposal, 3000);
    }
  }, [isTargetApproveSuccess]);

  function handleTargetApprove() {
    if (!isConnected) { openConnectModal(); return; }
    if (!guardianTarget) return;
    sendTargetApprove({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "approveRecovery",
      args: [guardianTarget],
    });
  }

  // targetThreshold > 0n evita executar antes do getGuardianConfig do alvo
  // carregar (mesma classe de corrida do P41, evitada aqui desde o início).
  const canTargetExecute =
    targetProposalStatus === "active" &&
    targetProposal &&
    targetThreshold > 0n &&
    targetProposal.approvalCount >= targetThreshold &&
    timelock !== undefined &&
    BigInt(Math.floor(Date.now() / 1000)) >= targetProposal.proposedAt + timelock;

  const {
    writeContract: sendTargetExecute,
    data: targetExecuteTxHash,
    isPending: isTargetExecutePending,
    isError: isTargetExecuteError,
    error: targetExecuteWriteError,
  } = useWriteContract();

  const { isLoading: isTargetExecuteConfirming, isSuccess: isTargetExecuteSuccess } =
    useWaitForTransactionReceipt({ hash: targetExecuteTxHash });

  useEffect(() => {
    if (isTargetExecuteSuccess) {
      queryClient.invalidateQueries();
      setTimeout(refetchTargetProposal, 3000);
    }
  }, [isTargetExecuteSuccess]);

  function handleTargetExecute() {
    if (!isConnected) { openConnectModal(); return; }
    if (!guardianTarget) return;
    sendTargetExecute({
      address: RECOVERY_MANAGER_ADDRESS,
      abi: RECOVERY_MANAGER_ABI,
      functionName: "executeRecovery",
      args: [guardianTarget],
    });
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  const canExecute =
    proposalStatus === "active" &&
    proposal &&
    proposal.approvalCount >= threshold &&
    BigInt(Math.floor(Date.now() / 1000)) >= proposal.proposedAt + 7n * 86400n;

  const isConfigBusy = isConfigPending || isConfigConfirming;

  return (
    <div>
      <h2>Social Recovery — @{username}</h2>
      <p className="muted" style={{ marginBottom: "1rem" }}>
        Guardians can help recover your identity if you lose access to your wallet.
        {timelock && ` Recovery requires ${Number(threshold)} of ${guardians.length} approvals plus a ${Number(timelock / 86400n)}-day timelock.`}
      </p>

      {!isConfigured && !showConfigForm && (
        <div className="card" style={{ borderColor: "#f0ad4e" }}>
          <p><strong>⚠ No guardians configured.</strong> Without guardians, losing your wallet means permanent loss of identity.</p>
          <div className="actions-row">
            <button onClick={() => setShowConfigForm(true)}>Configure Guardians</button>
          </div>
        </div>
      )}

      {/* ── Guardian configuration form ── */}
      {showConfigForm && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>
            {isConfigured ? "Reconfigure Guardians" : "Configure Guardians"}
          </h3>

          {guardianInputs.map((addr, idx) => (
            <div key={idx} className="guardian-row" style={{ display: "flex", gap: "0.5rem", marginBottom: "0.5rem", alignItems: "center" }}>
              <input
                type="text"
                placeholder="0x..."
                value={addr}
                onChange={(e) => updateGuardianField(idx, e.target.value)}
                style={{ flex: 1, fontFamily: "monospace" }}
              />
              <button
                onClick={() => removeGuardianField(idx)}
                disabled={guardianInputs.length <= 1}
                className="small-btn"
                title="Remove"
              >
                ✕
              </button>
              {idx === guardianInputs.length - 1 && (
                <button onClick={addGuardianField} className="small-btn" title="Add guardian">+</button>
              )}
            </div>
          ))}

          <div style={{ marginBottom: "0.75rem" }}>
            <label>
              Threshold (approvals needed):{" "}
              <input
                type="number"
                min={1}
                max={guardianInputs.filter((a) => a.trim()).length}
                value={thresholdInput}
                onChange={(e) => setThresholdInput(Number(e.target.value))}
                style={{ width: "60px" }}
              />
              {" of "}{guardianInputs.filter((a) => a.trim()).length}
            </label>
          </div>

          {configError && <p className="error-text">{configError}</p>}
          {isConfigError && (
            <p className="error-text">
              {configWriteError?.message?.includes("rejected_by_user")
                ? "Rejected on Ledger"
                : `Error: ${configWriteError?.message?.split("\n")[0]}`}
            </p>
          )}

          <div className="actions-row">
            <button onClick={handleConfigure} disabled={isConfigBusy}>
              {isConfigBusy ? "Confirm in wallet..." : isConfigured ? "Update Guardians" : "Set Guardians"}
            </button>
            <button onClick={() => { setShowConfigForm(false); resetConfig(); setConfigError(null); }}>
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* ── Current guardian list ── */}
      {isConfigured && !showConfigForm && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Guardians ({Number(threshold)} of {guardians.length})</h3>
          <ul style={{ listStyle: "none", padding: 0 }}>
            {guardians.map((g) => (
              <li key={g} style={{ fontFamily: "monospace", marginBottom: "0.25rem" }}>
                {formatAddress(g)}
                {g.toLowerCase() === connectedAddress?.toLowerCase() && <span className="status-badge status-badge--active" style={{ marginLeft: "0.5rem" }}>You</span>}
              </li>
            ))}
          </ul>
          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={() => { setGuardianInputs(guardians.map((g) => g)); setThresholdInput(Number(threshold)); setShowConfigForm(true); }}>
              Change Guardians
            </button>
          </div>
        </div>
      )}

      {/* ── Act as guardian for another identity (P39) ── */}
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Act as Guardian</h3>
        <p className="muted">
          If someone added you as a guardian, look up their username to help with their recovery.
        </p>
        <div style={{ display: "flex", gap: "0.5rem", marginBottom: "0.75rem" }}>
          <input
            type="text"
            placeholder="Their username"
            value={guardianTargetInput}
            onChange={(e) => setGuardianTargetInput(e.target.value)}
            style={{ flex: 1 }}
          />
          <button
            onClick={() => setGuardianTarget(guardianTargetInput.trim())}
            disabled={!guardianTargetInput.trim()}
          >
            Look up
          </button>
        </div>

        {guardianTarget && (
          <>
            {!targetIsGuardian && (
              <p className="muted">You are not a guardian for @{guardianTarget}.</p>
            )}

            {targetIsGuardian && targetProposalStatus === "none" && (
              <>
                <p className="muted">
                  No active recovery. If @{guardianTarget} lost access, propose a new controller wallet.
                </p>
                <input
                  type="text"
                  placeholder="New controller address (0x...)"
                  value={targetNewController}
                  onChange={(e) => setTargetNewController(e.target.value)}
                  style={{ width: "100%", fontFamily: "monospace", marginBottom: "0.5rem" }}
                />
                {targetProposeError && <p className="error-text">{targetProposeError}</p>}
                {isTargetProposeError && (
                  <p className="error-text">
                    {targetProposeWriteError?.message?.includes("rejected_by_user")
                      ? "Rejected on wallet"
                      : `Error: ${targetProposeWriteError?.message?.split("\n")[0]}`}
                  </p>
                )}
                <div className="actions-row">
                  <button onClick={handleTargetPropose} disabled={isTargetProposePending || isTargetProposeConfirming}>
                    {isTargetProposePending ? "Confirm in wallet..." : isTargetProposeConfirming ? "Waiting for network..." : "Propose Recovery"}
                  </button>
                </div>
              </>
            )}

            {targetProposalStatus === "active" && targetProposal && (
              <div>
                <p>
                  <strong>Proposed by:</strong> {formatAddress(targetProposal.proposedBy)}<br />
                  <strong>New controller:</strong> {formatAddress(targetProposal.newController)}<br />
                  <strong>Approvals:</strong> {Number(targetProposal.approvalCount)} of {Number(targetThreshold)}<br />
                  <strong>Timelock:</strong> {timeRemaining(targetProposal.proposedAt)}
                </p>

                {targetIsGuardian && !targetHasApproved && (
                  <div className="actions-row">
                    <button onClick={handleTargetApprove} disabled={isTargetApprovePending || isTargetApproveConfirming}>
                      {isTargetApprovePending ? "Confirm in wallet..." : isTargetApproveConfirming ? "Waiting for network..." : "Approve Recovery"}
                    </button>
                  </div>
                )}

                {targetIsGuardian && targetHasApproved && (
                  <p><span className="status-badge status-badge--active">✓ You approved</span></p>
                )}

                {isTargetApproveError && (
                  <p className="error-text">
                    {targetApproveWriteError?.message?.includes("rejected_by_user")
                      ? "Rejected on wallet"
                      : `Error: ${targetApproveWriteError?.message?.split("\n")[0]}`}
                  </p>
                )}

                {canTargetExecute && (
                  <div className="actions-row">
                    <button
                      onClick={handleTargetExecute}
                      disabled={isTargetExecutePending || isTargetExecuteConfirming}
                      style={{ background: "#d9534f", color: "#fff" }}
                    >
                      {isTargetExecutePending ? "Confirm in wallet..." : isTargetExecuteConfirming ? "Waiting for network..." : "▶ Execute Recovery Now"}
                    </button>
                  </div>
                )}

                {isTargetExecuteError && (
                  <p className="error-text">
                    {targetExecuteWriteError?.message?.includes("rejected_by_user")
                      ? "Rejected on wallet"
                      : `Error: ${targetExecuteWriteError?.message?.split("\n")[0]}`}
                  </p>
                )}
              </div>
            )}

            {targetProposalStatus === "executed" && targetProposal && (
              <p>
                <span className="status-badge status-badge--active">✓ Recovery executed</span>{" "}
                New controller: {formatAddress(targetProposal.newController)}.
              </p>
            )}

            {targetProposalStatus === "cancelled" && (
              <p><span className="status-badge status-badge--revoked">✕ Recovery cancelled</span></p>
            )}
          </>
        )}
      </div>

      {/* ── Active Proposal ── */}
      {proposalStatus === "active" && proposal && (
        <div className="card" style={{ borderColor: "#d9534f" }}>
          <h3 style={{ marginTop: 0, color: "#d9534f" }}>⚠ Recovery Proposed</h3>
          <p>
            <strong>Proposed by:</strong> {formatAddress(proposal.proposedBy)}<br />
            <strong>New controller:</strong> {formatAddress(proposal.newController)}<br />
            <strong>Approvals:</strong> {Number(proposal.approvalCount)} of {Number(threshold)}<br />
            <strong>Timelock:</strong> {timeRemaining(proposal.proposedAt)}
          </p>

          {isGuardian && !hasApproved && (
            <div className="actions-row">
              <button onClick={handleApprove} disabled={isApprovePending || isApproveConfirming}>
                {isApprovePending ? "Confirm in wallet..." : isApproveConfirming ? "Waiting for network..." : "Approve Recovery"}
              </button>
            </div>
          )}

          {isGuardian && hasApproved && (
            <p><span className="status-badge status-badge--active">✓ You approved</span></p>
          )}

          {isApproveError && (
            <p className="error-text">
              {approveWriteError?.message?.includes("rejected_by_user")
                ? "Rejected on wallet"
                : `Error: ${approveWriteError?.message?.split("\n")[0]}`}
            </p>
          )}

          {canExecute && (
            <div className="actions-row">
              <button onClick={handleExecute} disabled={isExecutePending || isExecuteConfirming} style={{ background: "#d9534f", color: "#fff" }}>
                {isExecutePending ? "Confirm in wallet..." : isExecuteConfirming ? "Waiting for network..." : "▶ Execute Recovery Now"}
              </button>
            </div>
          )}

          {isExecuteError && (
            <p className="error-text">
              {executeWriteError?.message?.includes("rejected_by_user")
                ? "Rejected on wallet"
                : `Error: ${executeWriteError?.message?.split("\n")[0]}`}
            </p>
          )}

          <div className="actions-row" style={{ marginTop: "1rem" }}>
            <button
              onClick={handleCancel}
              disabled={isCancelPending || isCancelConfirming}
              className="small-btn"
              style={{ color: "#888" }}
            >
              {isCancelPending || isCancelConfirming ? "Processing..." : "Cancel Proposal (controller only)"}
            </button>
          </div>

          {isCancelError && (
            <p className="error-text">
              {cancelWriteError?.message?.includes("rejected_by_user")
                ? "Rejected on Ledger"
                : `Error: ${cancelWriteError?.message?.split("\n")[0]}`}
            </p>
          )}
        </div>
      )}

      {/* ── No active proposal, guardian can propose ── */}
      {isConfigured && isGuardian && proposalStatus === "none" && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Propose Recovery</h3>
          <p className="muted">If the identity owner lost access, propose a new controller wallet.</p>
          <input
            type="text"
            placeholder="New controller address (0x...)"
            value={newController}
            onChange={(e) => setNewController(e.target.value)}
            style={{ width: "100%", fontFamily: "monospace", marginBottom: "0.5rem" }}
          />
          {proposeError && <p className="error-text">{proposeError}</p>}
          {isProposeError && (
            <p className="error-text">
              {proposeWriteError?.message?.includes("rejected_by_user")
                ? "Rejected on wallet"
                : `Error: ${proposeWriteError?.message?.split("\n")[0]}`}
            </p>
          )}
          <div className="actions-row">
            <button onClick={handlePropose} disabled={isProposePending || isProposeConfirming}>
              {isProposePending ? "Confirm in wallet..." : isProposeConfirming ? "Waiting for network..." : "Propose Recovery"}
            </button>
          </div>
        </div>
      )}

      {/* ── Executed / Cancelled proposal ── */}
      {proposalStatus === "executed" && (
        <div className="card" style={{ borderColor: "#5cb85c" }}>
          <p><span className="status-badge status-badge--active">✓ Recovery executed</span></p>
          <p className="muted">New controller: {formatAddress(proposal!.newController)}. You may need to reconnect with the new wallet.</p>
        </div>
      )}

      {proposalStatus === "cancelled" && (
        <div className="card" style={{ borderColor: "#888" }}>
          <p><span className="status-badge status-badge--revoked">✕ Recovery cancelled</span></p>
          <p className="muted">The controller cancelled the recovery proposal. No action needed.</p>
        </div>
      )}
    </div>
  );
}
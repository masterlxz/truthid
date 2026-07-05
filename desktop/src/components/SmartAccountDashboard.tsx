import { useMemo, useState } from "react";
import { useBalance } from "wagmi";
import { formatEther } from "viem";
import { useIdentity } from "../contexts/IdentityContext";
import { useSmartAccountActivity } from "../hooks/useSmartAccountActivity";
import { VAULT_REGISTRY_ADDRESS } from "../config/contracts";
import { DepositModal } from "./DepositModal";
import { WithdrawModal } from "./WithdrawModal";
import type { SmartAccountActivityType } from "../types";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const VAULT_DEPLOYED = VAULT_REGISTRY_ADDRESS !== ZERO_ADDRESS;

const ACTIVITY_LABELS: Record<SmartAccountActivityType, string> = {
  session_created: "Session created",
  session_revoked: "Session revoked",
  session_revoked_all: "All sessions revoked",
  device_registered: "Device registered",
  device_revoked: "Device revoked",
  vault_updated: "Vault updated",
};

const REVOKED_TYPES = new Set<SmartAccountActivityType>([
  "session_revoked",
  "session_revoked_all",
  "device_revoked",
]);

export function SmartAccountDashboard() {
  const { username, identityId, smartAccountAddress } = useIdentity();
  const [depositOpen, setDepositOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);

  const { data: balance, isLoading: isBalanceLoading } = useBalance({
    address: smartAccountAddress ?? undefined,
    query: { enabled: !!smartAccountAddress },
  });

  const { activities, isScanning, progress, error, rescan } = useSmartAccountActivity(identityId);

  const summary = useMemo(() => {
    const totals = {
      session: { count: 0, costWei: 0n },
      device: { count: 0, costWei: 0n },
      vault: { count: 0, costWei: 0n },
    };
    for (const activity of activities) {
      const bucket = activity.type.startsWith("session")
        ? totals.session
        : activity.type.startsWith("device")
          ? totals.device
          : totals.vault;
      bucket.count += 1;
      bucket.costWei += activity.costWei;
    }
    return totals;
  }, [activities]);

  const sortedActivities = useMemo(() => activities.slice().reverse(), [activities]);

  return (
    <div>
      <h2>@{username}</h2>
      <h3>Smart Account Dashboard</h3>

      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Balance</p>
        {isBalanceLoading && <p className="muted">Loading...</p>}
        {!isBalanceLoading && balance && (
          <strong style={{ fontSize: "1.4em" }}>{formatEther(balance.value)} ETH</strong>
        )}
        {smartAccountAddress && (
          <p className="muted" style={{ marginTop: "0.5rem", fontSize: "0.85rem" }} title={smartAccountAddress}>
            {smartAccountAddress.slice(0, 8)}…{smartAccountAddress.slice(-6)}
          </p>
        )}
        <div className="actions-row">
          <button onClick={() => setDepositOpen(true)}>Deposit</button>
          <button onClick={() => setWithdrawOpen(true)} disabled={!balance || balance.value === 0n}>
            Withdraw
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Cost by type</h3>
        <div style={{ display: "flex", gap: "1.5rem", flexWrap: "wrap" }}>
          <div>
            <p className="muted" style={{ margin: 0 }}>Sessions</p>
            <strong>{summary.session.count}</strong>
            <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
              {formatEther(summary.session.costWei)} ETH
            </p>
          </div>
          <div>
            <p className="muted" style={{ margin: 0 }}>Devices</p>
            <strong>{summary.device.count}</strong>
            <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
              {formatEther(summary.device.costWei)} ETH
            </p>
          </div>
          <div>
            <p className="muted" style={{ margin: 0 }}>Vault</p>
            {VAULT_DEPLOYED ? (
              <>
                <strong>{summary.vault.count}</strong>
                <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
                  {formatEther(summary.vault.costWei)} ETH
                </p>
              </>
            ) : (
              <p className="muted" style={{ margin: 0 }}>Not available yet</p>
            )}
          </div>
        </div>
      </div>

      <div className="card">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h3 style={{ marginTop: 0 }}>Activity</h3>
          <button className="topbar-btn" style={{ fontSize: "0.8rem" }} onClick={rescan}>
            Refresh activity
          </button>
        </div>

        {isScanning && activities.length === 0 && (
          <p className="muted">
            Scanning transaction history{progress ? ` (block ${progress.scannedTo} of ${progress.latest})` : "…"}
          </p>
        )}
        {isScanning && activities.length > 0 && <p className="muted">Updating…</p>}

        {error && (
          <div>
            <p className="error-text">Failed to load activity: {error.message.split("\n")[0]}</p>
            <button onClick={rescan}>Retry</button>
          </div>
        )}

        {!isScanning && !error && activities.length === 0 && (
          <p className="muted">No activity yet.</p>
        )}

        {sortedActivities.map((activity) => {
          const isRevoked = REVOKED_TYPES.has(activity.type);
          const hashShort = `${activity.hash.slice(0, 10)}…${activity.hash.slice(-6)}`;
          const date = new Date(activity.timestamp * 1000).toLocaleString();
          return (
            <div key={`${activity.hash}-${activity.logIndex}`} className="card">
              <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
                <span className={`status-badge ${isRevoked ? "status-badge--revoked" : "status-badge--active"}`}>
                  {ACTIVITY_LABELS[activity.type]}
                </span>
                <code className="address">{hashShort}</code>
              </div>
              <span className="muted">{date}</span>
              <span className="muted"> · {formatEther(activity.costWei)} ETH</span>
            </div>
          );
        })}
      </div>

      {depositOpen && smartAccountAddress && (
        <div className="modal-overlay" onClick={() => setDepositOpen(false)}>
          <div className="modal-box" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2 className="modal-title">Deposit</h2>
              <button className="modal-close" onClick={() => setDepositOpen(false)}>✕</button>
            </div>
            <DepositModal smartAccountAddress={smartAccountAddress} />
          </div>
        </div>
      )}

      {withdrawOpen && smartAccountAddress && balance && (
        <div className="modal-overlay" onClick={() => setWithdrawOpen(false)}>
          <div className="modal-box" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2 className="modal-title">Withdraw</h2>
              <button className="modal-close" onClick={() => setWithdrawOpen(false)}>✕</button>
            </div>
            <WithdrawModal
              smartAccountAddress={smartAccountAddress}
              availableBalance={balance.value}
              onClose={() => setWithdrawOpen(false)}
            />
          </div>
        </div>
      )}
    </div>
  );
}

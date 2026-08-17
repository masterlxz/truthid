import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { useBalance } from "wagmi";
import { formatEther } from "viem";
import { useIdentity } from "../contexts/IdentityContext";
import { useSmartAccountActivity } from "../hooks/useSmartAccountActivity";
import { formatDateTime } from "../i18n/formatDate";
import { DepositModal } from "./DepositModal";
import { WithdrawModal } from "./WithdrawModal";
import type { SmartAccountActivityType } from "../types";

const REVOKED_TYPES = new Set<SmartAccountActivityType>([
  "session_revoked",
  "session_revoked_all",
  "device_revoked",
]);

export function SmartAccountDashboard() {
  const { t, i18n } = useTranslation();
  const { username, identityId, smartAccountAddress } = useIdentity();
  const [depositOpen, setDepositOpen] = useState(false);
  const [withdrawOpen, setWithdrawOpen] = useState(false);

  const activityLabels: Record<SmartAccountActivityType, string> = {
    session_created: t("smartAccountDashboard.activity.labels.session_created"),
    session_revoked: t("smartAccountDashboard.activity.labels.session_revoked"),
    session_revoked_all: t("smartAccountDashboard.activity.labels.session_revoked_all"),
    device_registered: t("smartAccountDashboard.activity.labels.device_registered"),
    device_revoked: t("smartAccountDashboard.activity.labels.device_revoked"),
    vault_updated: t("smartAccountDashboard.activity.labels.vault_updated"),
  };

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
      <h3>{t("smartAccountDashboard.title")}</h3>

      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("smartAccountDashboard.balance.label")}</p>
        {isBalanceLoading && <p className="muted">{t("smartAccountDashboard.balance.loading")}</p>}
        {!isBalanceLoading && balance && (
          <strong style={{ fontSize: "1.4em" }}>{formatEther(balance.value)} ETH</strong>
        )}
        {smartAccountAddress && (
          <p className="muted" style={{ marginTop: "0.5rem", fontSize: "0.85rem" }} title={smartAccountAddress}>
            {smartAccountAddress.slice(0, 8)}…{smartAccountAddress.slice(-6)}
          </p>
        )}
        <div className="actions-row">
          <button onClick={() => setDepositOpen(true)}>{t("smartAccountDashboard.actions.deposit")}</button>
          <button onClick={() => setWithdrawOpen(true)} disabled={!balance || balance.value === 0n}>
            {t("smartAccountDashboard.actions.withdraw")}
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("smartAccountDashboard.costByType.title")}</h3>
        <div style={{ display: "flex", gap: "1.5rem", flexWrap: "wrap" }}>
          <div>
            <p className="muted" style={{ margin: 0 }}>{t("smartAccountDashboard.costByType.sessions")}</p>
            <strong>{summary.session.count}</strong>
            <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
              {formatEther(summary.session.costWei)} ETH
            </p>
          </div>
          <div>
            <p className="muted" style={{ margin: 0 }}>{t("smartAccountDashboard.costByType.devices")}</p>
            <strong>{summary.device.count}</strong>
            <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
              {formatEther(summary.device.costWei)} ETH
            </p>
          </div>
          <div>
            <p className="muted" style={{ margin: 0 }}>{t("smartAccountDashboard.costByType.vault")}</p>
            <strong>{summary.vault.count}</strong>
            <p className="muted" style={{ margin: 0, fontSize: "0.85rem" }}>
              {formatEther(summary.vault.costWei)} ETH
            </p>
          </div>
        </div>
      </div>

      <div className="card">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h3 style={{ marginTop: 0 }}>{t("smartAccountDashboard.activity.title")}</h3>
          <button className="topbar-btn" style={{ fontSize: "0.8rem" }} onClick={rescan}>
            {t("smartAccountDashboard.activity.refresh")}
          </button>
        </div>

        {isScanning && activities.length === 0 && (
          <p className="muted">
            {progress
              ? t("smartAccountDashboard.activity.scanningProgress", {
                  scannedTo: progress.scannedTo,
                  latest: progress.latest,
                })
              : t("smartAccountDashboard.activity.scanning")}
          </p>
        )}
        {isScanning && activities.length > 0 && <p className="muted">{t("smartAccountDashboard.activity.updating")}</p>}

        {error && (
          <div>
            <p className="error-text">
              {t("smartAccountDashboard.activity.failedToLoad", { error: error.message.split("\n")[0] })}
            </p>
            <button onClick={rescan}>{t("smartAccountDashboard.activity.retry")}</button>
          </div>
        )}

        {!isScanning && !error && activities.length === 0 && (
          <p className="muted">{t("smartAccountDashboard.activity.empty")}</p>
        )}

        {sortedActivities.map((activity) => {
          const isRevoked = REVOKED_TYPES.has(activity.type);
          const hashShort = `${activity.hash.slice(0, 10)}…${activity.hash.slice(-6)}`;
          const date = formatDateTime(activity.timestamp, i18n.language);
          return (
            <div key={`${activity.hash}-${activity.logIndex}`} className="card">
              <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
                <span className={`status-badge ${isRevoked ? "status-badge--revoked" : "status-badge--active"}`}>
                  {activityLabels[activity.type]}
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
              <h2 className="modal-title">{t("smartAccountDashboard.modal.deposit")}</h2>
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
              <h2 className="modal-title">{t("smartAccountDashboard.modal.withdraw")}</h2>
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

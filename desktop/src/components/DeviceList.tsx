import { useTranslation } from "react-i18next";
import { formatDate } from "../i18n/formatDate";
import type { DeviceInfo } from "../types";

export function DeviceList({
  devices,
  revokingPubKey,
  isRevokePending,
  isRevokeConfirming,
  onRevoke,
}: {
  devices: DeviceInfo[];
  revokingPubKey: string | null;
  isRevokePending: boolean;
  isRevokeConfirming: boolean;
  onRevoke: (pubKey: string) => void;
}) {
  const { t, i18n } = useTranslation();

  if (devices.length === 0) {
    return <p className="muted">{t("deviceList.empty")}</p>;
  }

  return (
    <div>
      <h3>{t("deviceList.title")}</h3>
      {devices.map((device) => {
        const isBeingRevoked = revokingPubKey === device.pubKey;
        // addedAt vem em segundos (Unix timestamp do bloco)
        const addedDate = formatDate(Number(device.addedAt), i18n.language);

        return (
          <div key={device.pubKey} className={`card${device.revoked ? " is-revoked" : ""}`}>
            <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
              <strong>{device.label}</strong>
              <span className={`status-badge ${device.revoked ? "status-badge--revoked" : "status-badge--active"}`}>
                {device.revoked ? t("deviceList.status.revoked") : t("deviceList.status.active")}
              </span>
            </div>
            <code className="address">
              {device.pubKey.slice(0, 10)}…{device.pubKey.slice(-6)}
            </code>
            <span className="muted"> · {t("deviceList.addedOn", { date: addedDate })}</span>
            {!device.revoked && (
              <div className="actions-row">
                <button
                  onClick={() => onRevoke(device.pubKey)}
                  disabled={isRevokePending || isRevokeConfirming}
                >
                  {isBeingRevoked && isRevokePending
                    ? t("deviceList.actions.confirmInWallet")
                    : isBeingRevoked && isRevokeConfirming
                    ? t("deviceList.actions.waitingForNetwork")
                    : t("deviceList.actions.revoke")}
                </button>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

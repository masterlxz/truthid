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
  if (devices.length === 0) {
    return <p className="muted">No devices registered yet.</p>;
  }

  return (
    <div>
      <h3>Devices</h3>
      {devices.map((device) => {
        const isBeingRevoked = revokingPubKey === device.pubKey;
        // addedAt vem em segundos (Unix timestamp do bloco)
        const addedDate = new Date(Number(device.addedAt) * 1000).toLocaleDateString();

        return (
          <div key={device.pubKey} className={`card${device.revoked ? " is-revoked" : ""}`}>
            <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
              <strong>{device.label}</strong>
              <span className={`status-badge ${device.revoked ? "status-badge--revoked" : "status-badge--active"}`}>
                {device.revoked ? "Revoked" : "✓ Active"}
              </span>
            </div>
            <code className="address">
              {device.pubKey.slice(0, 10)}…{device.pubKey.slice(-6)}
            </code>
            <span className="muted"> · Added on {addedDate}</span>
            {!device.revoked && (
              <div className="actions-row">
                <button
                  onClick={() => onRevoke(device.pubKey)}
                  disabled={isRevokePending || isRevokeConfirming}
                >
                  {isBeingRevoked && isRevokePending
                    ? "Confirm in wallet..."
                    : isBeingRevoked && isRevokeConfirming
                    ? "Waiting for network..."
                    : "Revoke"}
                </button>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

import { useState } from "react";
import type { Address } from "viem";
import { QRCodeSVG } from "qrcode.react";

export function DepositModal({ smartAccountAddress }: { smartAccountAddress: Address }) {
  const [copied, setCopied] = useState(false);
  const depositUri = `ethereum:${smartAccountAddress}`;

  async function handleCopy() {
    await navigator.clipboard.writeText(smartAccountAddress);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "1rem" }}>
      <p className="muted" style={{ margin: 0, textAlign: "center" }}>
        Send ETH to your smart account address to fund future operations.
      </p>

      <div className="donate-qr-wrapper">
        <QRCodeSVG
          value={depositUri}
          size={180}
          fgColor="#0b0f14"
          bgColor="#ffffff"
        />
      </div>

      <code className="donate-address">{smartAccountAddress}</code>

      <div className="actions-row" style={{ justifyContent: "center" }}>
        <button onClick={handleCopy}>
          {copied ? "✓ Copied!" : "Copy address"}
        </button>
      </div>

      <p className="muted" style={{ margin: 0, fontSize: "0.8em", textAlign: "center" }}>
        Base Mainnet only
      </p>
    </div>
  );
}

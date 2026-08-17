import { useState } from "react";
import type { Address } from "viem";
import { QRCodeSVG } from "qrcode.react";
import { useTranslation } from "react-i18next";

export function DepositModal({ smartAccountAddress }: { smartAccountAddress: Address }) {
  const { t } = useTranslation();
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
        {t("depositModal.description")}
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
          {copied ? t("depositModal.copied") : t("depositModal.copyAddress")}
        </button>
      </div>

      <p className="muted" style={{ margin: 0, fontSize: "0.8em", textAlign: "center" }}>
        {t("depositModal.footnote")}
      </p>
    </div>
  );
}

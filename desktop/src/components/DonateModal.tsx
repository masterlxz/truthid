import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { useTranslation } from "react-i18next";

const DONATE_ADDRESS = "0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265";
const DONATE_URI = `ethereum:${DONATE_ADDRESS}`;

export function DonateModal() {
  const { t } = useTranslation();
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(DONATE_ADDRESS);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "1rem" }}>
      <p className="muted" style={{ margin: 0, textAlign: "center" }}>
        {t("donateModal.description")}
      </p>

      <div className="donate-qr-wrapper">
        <QRCodeSVG
          value={DONATE_URI}
          size={180}
          fgColor="#0b0f14"
          bgColor="#ffffff"
        />
      </div>

      <code className="donate-address">{DONATE_ADDRESS}</code>

      <div className="actions-row" style={{ justifyContent: "center" }}>
        <button onClick={handleCopy}>
          {copied ? t("donateModal.copied") : t("donateModal.copyAddress")}
        </button>
      </div>

      <p className="muted" style={{ margin: 0, fontSize: "0.8em", textAlign: "center" }}>
        {t("donateModal.footnote")}
      </p>
    </div>
  );
}

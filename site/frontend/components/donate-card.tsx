"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";

const DONATE_ADDRESS = "0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265";
const DONATE_URI = `ethereum:${DONATE_ADDRESS}`;

// QR + address + copy button for the /donate page. Same address as the
// desktop app's DonateModal. The QR sits on a white tile regardless of theme
// so scanners get the contrast they need.
export function DonateCard() {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(DONATE_ADDRESS);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard can be blocked (insecure context, permissions); the address
      // is still on screen to copy by hand.
    }
  }

  return (
    <div className="flex flex-col items-center">
      <div className="mb-5 inline-flex rounded-xl bg-white p-4">
        <QRCodeSVG value={DONATE_URI} size={200} fgColor="#000000" bgColor="#ffffff" />
      </div>
      <code className="mb-2 break-all text-xs">{DONATE_ADDRESS}</code>
      <p className="mb-6 text-sm text-fd-muted-foreground">
        Any EVM-compatible chain (ETH, Base, Polygon…) · 0.001 ETH suggested
      </p>
      <button
        type="button"
        onClick={handleCopy}
        className={`cursor-pointer rounded-lg border border-fd-primary px-5 py-2 text-sm transition-colors ${
          copied ? "bg-fd-primary text-fd-primary-foreground" : "text-fd-primary"
        }`}
      >
        {copied ? "✓ Copied!" : "Copy address"}
      </button>
    </div>
  );
}

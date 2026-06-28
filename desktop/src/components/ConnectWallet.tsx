import { useState } from "react";
import { useConnect } from "wagmi";
import { ConnectLedger } from "./ConnectLedger";

function IconWalletConnect() {
  return (
    <svg width="36" height="36" viewBox="0 0 36 36" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="36" height="36" rx="9" fill="#3396FF"/>
      <path
        d="M9.5 16.2C13.8 12.2 22.2 12.2 26.5 16.2L27.2 16.9C27.5 17.2 27.5 17.6 27.2 17.9L25.1 19.9C25 20 24.7 20 24.6 19.9L23.7 19C21 16.5 15 16.5 12.3 19L11.4 19.9C11.3 20 11 20 10.9 19.9L8.8 17.9C8.5 17.6 8.5 17.2 8.8 16.9L9.5 16.2Z"
        fill="white"
      />
      <path
        d="M15 21.5L16.7 19.9C17.1 19.5 17.9 19.5 18.3 19.9L20 21.5C20.4 21.9 20.4 22.5 20 22.9L18.3 24.5C17.9 24.9 17.1 24.9 16.7 24.5L15 22.9C14.6 22.5 14.6 21.9 15 21.5Z"
        fill="white"
      />
    </svg>
  );
}

function IconLedger() {
  return (
    <svg width="36" height="36" viewBox="0 0 36 36" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="36" height="36" rx="9" fill="#1D1D1B"/>
      <rect x="12" y="10" width="4.5" height="16" rx="1" fill="white"/>
      <rect x="12" y="21.5" width="14" height="4.5" rx="1" fill="white"/>
    </svg>
  );
}

export function ConnectWallet({ asModal, onClose }: { asModal?: boolean; onClose?: () => void }) {
  const { connect, connectors } = useConnect();
  const [showLedger, setShowLedger] = useState(false);

  const walletConnectConnector = connectors.find((c) => c.id === "walletConnect");

  if (showLedger) {
    return (
      <div className={asModal ? undefined : "wallet-screen"}>
        <ConnectLedger onBack={() => setShowLedger(false)} />
      </div>
    );
  }

  return (
    <div className={asModal ? undefined : "wallet-screen"}>
      <div className="wallet-card">
        {asModal && onClose && (
          <button className="modal-close" onClick={onClose} style={{ alignSelf: "flex-end" }}>✕</button>
        )}
        <div className="wallet-screen-header">
          <div className="wallet-screen-logo">
            <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
              <path
                d="M14 2L24 8V20L14 26L4 20V8L14 2Z"
                fill="none"
                stroke="#4DD0E1"
                strokeWidth="1.5"
              />
              <path
                d="M14 7L20 10.5V17.5L14 21L8 17.5V10.5L14 7Z"
                fill="rgba(77,208,225,0.15)"
                stroke="#4DD0E1"
                strokeWidth="1"
              />
              <path d="M14 11V17M11 14H17" stroke="#4DD0E1" strokeWidth="1.5" strokeLinecap="round"/>
            </svg>
            TruthID
          </div>
          <p className="wallet-screen-tagline">Sign in to your decentralized identity</p>
        </div>

        <div className="wallet-options">
          {walletConnectConnector && (
            <button
              className="wallet-option"
              onClick={() => connect({ connector: walletConnectConnector })}
            >
              <span className="wallet-option-icon">
                <IconWalletConnect />
              </span>
              <span className="wallet-option-name">WalletConnect</span>
              <span className="wallet-option-arrow">›</span>
            </button>
          )}

          <button
            className="wallet-option"
            onClick={() => setShowLedger(true)}
          >
            <span className="wallet-option-icon">
              <IconLedger />
            </span>
            <span className="wallet-option-name">Ledger</span>
            <span className="wallet-option-arrow">›</span>
          </button>
        </div>
      </div>
    </div>
  );
}

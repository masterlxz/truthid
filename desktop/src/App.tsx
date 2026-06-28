import { useState, useEffect } from "react";
import { useAccount, useReadContract, useSwitchChain, useDisconnect } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { base } from "wagmi/chains";
import { ConnectWallet } from "./components/ConnectWallet";
import { CreateIdentity } from "./components/CreateIdentity";
import { ManageDevices } from "./components/ManageDevices";
import { ActiveSessions } from "./components/ActiveSessions";
import { QuickLogin } from "./components/QuickLogin";
import { IdentityProvider } from "./contexts/IdentityContext";
import { WalletModalContext } from "./contexts/WalletModalContext";
import { useStoredUsername } from "./hooks/useStoredUsername";
import { useUpdateCheck } from "./hooks/useUpdateCheck";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "./config/contracts";
import "./App.css";

type Tab = "devices" | "sessions";

function LogoIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 28 28" fill="none">
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
  );
}

function App() {
  const { isConnected, address, chainId } = useAccount();
  const { disconnect } = useDisconnect();
  const [activeTab, setActiveTab] = useState<Tab>("devices");
  const [loginOpen, setLoginOpen] = useState(false);
  const [connectModalOpen, setConnectModalOpen] = useState(false);
  const queryClient = useQueryClient();

  const { username: storedUsername, save: saveUsername, clear: clearUsername } = useStoredUsername();
  const { updateVersion, updateUrl } = useUpdateCheck();
  const [updateDismissed, setUpdateDismissed] = useState(false);

  const isWrongNetwork = isConnected && chainId !== base.id;
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const {
    data: onChainUsername,
    isLoading: isLoadingUsername,
    isError: isIdentityError,
    error: identityError,
    refetch: refetchIdentity,
  } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: [address!],
    query: { enabled: !!address && !isWrongNetwork },
  });

  // Save on-chain verified username to localStorage whenever we read it
  useEffect(() => {
    if (onChainUsername) saveUsername(onChainUsername as string);
  }, [onChainUsername]);

  // Displayed username: on-chain (verified) takes priority, falls back to localStorage
  const displayUsername = (isConnected && !isWrongNetwork && (onChainUsername as string | undefined)) || storedUsername;

  // Only block rendering with a loading state when we have no cached identity to show
  const isLoadingIdentity = isConnected && !isWrongNetwork && isLoadingUsername && !storedUsername;

  // ── No identity at all → full-screen login ───────────────────────────────
  if (!displayUsername && !isConnected) {
    return <ConnectWallet />;
  }

  function handleLogout() {
    clearUsername();
    disconnect();
  }

  // ── App shell ─────────────────────────────────────────────────────────────
  return (
    <WalletModalContext.Provider value={{ openConnectModal: () => setConnectModalOpen(true) }}>
      <div className="app-shell">
        <header className="topbar">
          <div className="topbar-left">
            <LogoIcon />
            TruthID
          </div>
          <div className="topbar-right">
            {displayUsername && (
              <button className="topbar-btn" onClick={() => setLoginOpen(true)}>
                ⎋ Login
              </button>
            )}
            {displayUsername && (
              <span className="topbar-username">@{displayUsername}</span>
            )}
            {displayUsername && (
              <button
                className="topbar-btn"
                onClick={() => queryClient.invalidateQueries()}
                title="Refresh"
              >
                ↻
              </button>
            )}
            {isConnected ? (
              <button
                className="topbar-btn topbar-btn-danger"
                onClick={() => disconnect()}
                title="Disconnect wallet"
              >
                Disconnect wallet
              </button>
            ) : (
              <button
                className="topbar-btn"
                onClick={() => setConnectModalOpen(true)}
              >
                Connect wallet
              </button>
            )}
            <button
              className="topbar-btn topbar-btn-danger"
              onClick={handleLogout}
              title="Log out and forget this identity"
            >
              Log out
            </button>
          </div>
        </header>

        {updateVersion && !updateDismissed && (
          <div className="update-banner">
            <span>⬆ TruthID {updateVersion} available</span>
            <a href={updateUrl} target="_blank" rel="noreferrer" className="update-banner-link">
              Download
            </a>
            <button className="update-banner-dismiss" onClick={() => setUpdateDismissed(true)}>
              ✕
            </button>
          </div>
        )}

        <main className="main-content">
          {isWrongNetwork && (
            <div className="card">
              <p>Wrong network. TruthID runs on Base Mainnet.</p>
              <button onClick={() => switchChain({ chainId: base.id })} disabled={isSwitching}>
                {isSwitching ? "Switching..." : "Switch to Base Mainnet"}
              </button>
            </div>
          )}

          {!isWrongNetwork && isLoadingIdentity && (
            <p className="muted">Loading...</p>
          )}

          {!isWrongNetwork && !isLoadingIdentity && isIdentityError && !storedUsername && (
            <div className="card">
              <p className="error-text">
                Failed to load identity: {identityError?.message?.split("\n")[0]}
              </p>
              <button onClick={() => refetchIdentity()}>Try again</button>
            </div>
          )}

          {/* First-time user: connected, no on-chain identity, nothing in localStorage */}
          {isConnected && !isWrongNetwork && !isLoadingIdentity && !onChainUsername && !storedUsername && (
            <CreateIdentity />
          )}

          {displayUsername && (
            <IdentityProvider username={displayUsername}>
              <nav className="tabs">
                <button
                  onClick={() => setActiveTab("devices")}
                  disabled={activeTab === "devices"}
                >
                  Devices
                </button>
                <button
                  onClick={() => setActiveTab("sessions")}
                  disabled={activeTab === "sessions"}
                >
                  Active Sessions
                </button>
              </nav>

              {activeTab === "devices" && <ManageDevices />}
              {activeTab === "sessions" && <ActiveSessions />}
            </IdentityProvider>
          )}
        </main>

        {loginOpen && (
          <div className="modal-overlay" onClick={() => setLoginOpen(false)}>
            <div className="modal-box" onClick={(e) => e.stopPropagation()}>
              <div className="modal-header">
                <h2 className="modal-title">Desktop Login</h2>
                <button className="modal-close" onClick={() => setLoginOpen(false)}>✕</button>
              </div>
              <QuickLogin />
            </div>
          </div>
        )}

        {connectModalOpen && (
          <div className="modal-overlay" onClick={() => setConnectModalOpen(false)}>
            <div className="modal-box" onClick={(e) => e.stopPropagation()}>
              <ConnectWallet asModal onClose={() => setConnectModalOpen(false)} />
            </div>
          </div>
        )}
      </div>
    </WalletModalContext.Provider>
  );
}

export default App;

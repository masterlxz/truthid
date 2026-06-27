import { useState } from "react";
import { useAccount, useReadContract, useSwitchChain } from "wagmi";
import { base } from "wagmi/chains";
import { ConnectWallet } from "./components/ConnectWallet";
import { CreateIdentity } from "./components/CreateIdentity";
import { ManageDevices } from "./components/ManageDevices";
import { ActiveSessions } from "./components/ActiveSessions";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "./config/contracts";
import "./App.css";

type Tab = "devices" | "sessions";

function App() {
  const { isConnected, address, chainId } = useAccount();
  const [activeTab, setActiveTab] = useState<Tab>("devices");

  const isWrongNetwork = isConnected && chainId !== base.id;
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const {
    data: username,
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

  const hasIdentity = !!username;
  const isLoadingIdentity = isConnected && !isWrongNetwork && isLoadingUsername;

  return (
    <main className="container">
      <h1>TruthID</h1>
      <ConnectWallet />

      {isWrongNetwork && (
        <div className="card">
          <p>Wrong network. TruthID runs on Base Mainnet.</p>
          <button
            onClick={() => switchChain({ chainId: base.id })}
            disabled={isSwitching}
          >
            {isSwitching ? "Switching..." : "Switch to Base Mainnet"}
          </button>
        </div>
      )}

      {isLoadingIdentity && <p className="muted">Loading...</p>}

      {isConnected && !isWrongNetwork && !isLoadingIdentity && isIdentityError && (
        <div className="card">
          <p className="error-text">
            Failed to load identity: {identityError?.message?.split("\n")[0]}
          </p>
          <button onClick={() => refetchIdentity()}>Try again</button>
        </div>
      )}

      {isConnected && !isWrongNetwork && !isLoadingIdentity && !isIdentityError && !hasIdentity && (
        <CreateIdentity />
      )}

      {isConnected && !isWrongNetwork && !isLoadingIdentity && !isIdentityError && hasIdentity && (
        <>
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
              Active sessions
            </button>
          </nav>

          {activeTab === "devices" && <ManageDevices username={username!} />}
          {activeTab === "sessions" && <ActiveSessions username={username!} />}
        </>
      )}
    </main>
  );
}

export default App;

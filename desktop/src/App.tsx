import { useState } from "react";
import { useAccount, useReadContract, useSwitchChain } from "wagmi";
import { baseSepolia } from "wagmi/chains";
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

  const isWrongNetwork = isConnected && chainId !== baseSepolia.id;
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const { data: username, isLoading: isLoadingUsername } = useReadContract({
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
        <div>
          <p>Rede incorreta. TruthID usa a Base Sepolia.</p>
          <button
            onClick={() => switchChain({ chainId: baseSepolia.id })}
            disabled={isSwitching}
          >
            {isSwitching ? "Trocando..." : "Trocar para Base Sepolia"}
          </button>
        </div>
      )}

      {isLoadingIdentity && <p>Carregando...</p>}

      {isConnected && !isWrongNetwork && !isLoadingIdentity && !hasIdentity && (
        <CreateIdentity />
      )}

      {isConnected && !isWrongNetwork && !isLoadingIdentity && hasIdentity && (
        <>
          <nav style={{ marginBottom: "1.5rem" }}>
            <button
              onClick={() => setActiveTab("devices")}
              disabled={activeTab === "devices"}
              style={{ marginRight: "0.5rem" }}
            >
              Dispositivos
            </button>
            <button
              onClick={() => setActiveTab("sessions")}
              disabled={activeTab === "sessions"}
            >
              Sessões ativas
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

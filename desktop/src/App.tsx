import { useAccount, useReadContract, useSwitchChain } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { ConnectWallet } from "./components/ConnectWallet";
import { CreateIdentity } from "./components/CreateIdentity";
import { ManageDevices } from "./components/ManageDevices";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "./config/contracts";
import "./App.css";

function App() {
  const { isConnected, address, chainId } = useAccount();

  // Verifica se a carteira está na rede certa (Base Sepolia = chain 84532)
  const isWrongNetwork = isConnected && chainId !== baseSepolia.id;

  // useSwitchChain: pede ao MetaMask para trocar de rede
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const { data: username, isLoading: isLoadingUsername } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: [address!],
    // Só lê se estiver na rede certa — evita erros de "contrato não existe"
    query: { enabled: !!address && !isWrongNetwork },
  });

  const hasIdentity = !!username;
  // Enquanto a leitura não terminar, não sabemos ainda qual tela mostrar
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
      {isConnected && !isWrongNetwork && !isLoadingIdentity && !hasIdentity && <CreateIdentity />}
      {isConnected && !isWrongNetwork && !isLoadingIdentity && hasIdentity && <ManageDevices username={username!} />}
    </main>
  );
}

export default App;

import { useAccount } from "wagmi";
import { ConnectWallet } from "./components/ConnectWallet";
import { CreateIdentity } from "./components/CreateIdentity";
import "./App.css";

function App() {
  const { isConnected } = useAccount();

  return (
    <main className="container">
      <h1>TruthID</h1>
      <ConnectWallet />
      {isConnected && <CreateIdentity />}
    </main>
  );
}

export default App;

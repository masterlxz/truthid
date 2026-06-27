import { useAccount, useConnect, useDisconnect } from "wagmi";
import { ConnectLedger } from "./ConnectLedger";

export function ConnectWallet() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected) {
    return (
      <div className="card actions-row" style={{ alignItems: "center", justifyContent: "space-between" }}>
        <p style={{ margin: 0 }}>
          Conectado: <code className="address">{address}</code>
        </p>
        <button onClick={() => disconnect()}>Desconectar</button>
      </div>
    );
  }

  return (
    <div className="card">
      <div className="actions-row">
        {connectors.map((connector) => (
          <button key={connector.id} onClick={() => connect({ connector })}>
            Conectar com {connector.name}
          </button>
        ))}
      </div>
      <div className="actions-row">
        <ConnectLedger />
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { ledger, setLedgerAccountIndex } from "../connectors/ledger";

// Mensagem mostrada conforme o rótulo de erro que o comando Rust devolve
// (ver classify_error em desktop/src-tauri/src/ledger.rs).
const INSTRUCTIONS: Record<string, string> = {
  not_connected: "Conecte sua Ledger por USB.",
  locked: "Desbloqueie a Ledger digitando o PIN nos botões físicos do dispositivo.",
  wrong_app: "Abra o app Ethereum na Ledger.",
};

export function ConnectLedger() {
  const { connectAsync } = useConnect();
  const [polling, setPolling] = useState(false);
  const [status, setStatus] = useState("not_connected");
  const [accountIndex, setAccountIndex] = useState(0);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  function startPolling() {
    setStatus("not_connected");
    setPolling(true);

    intervalRef.current = setInterval(async () => {
      try {
        setLedgerAccountIndex(accountIndex);
        await invoke<string>("get_ledger_address", { accountIndex });
        if (intervalRef.current) clearInterval(intervalRef.current);
        await connectAsync({ connector: ledger });
        setPolling(false);
      } catch (e) {
        setStatus(String(e));
      }
    }, 1000);
  }

  function cancelPolling() {
    if (intervalRef.current) clearInterval(intervalRef.current);
    setPolling(false);
  }

  if (polling) {
    return (
      <div className="actions-row" style={{ alignItems: "center" }}>
        <p className="muted" style={{ margin: 0 }}>
          {INSTRUCTIONS[status] ?? `Aguardando Ledger... (${status})`}
        </p>
        <button onClick={cancelPolling}>Cancelar</button>
      </div>
    );
  }

  return (
    <div className="actions-row" style={{ alignItems: "center" }}>
      <select
        value={accountIndex}
        onChange={(e) => setAccountIndex(Number(e.target.value))}
        style={{ padding: "0.25rem 0.5rem" }}
      >
        {[0, 1, 2, 3, 4].map((i) => (
          <option key={i} value={i}>Conta {i}</option>
        ))}
      </select>
      <button onClick={startPolling}>Conectar Ledger</button>
    </div>
  );
}

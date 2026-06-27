import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

// Mensagem mostrada conforme o rótulo de erro que o comando Rust devolve
// (ver classify_error em desktop/src-tauri/src/ledger.rs).
const INSTRUCTIONS: Record<string, string> = {
  not_connected: "Conecte sua Ledger por USB.",
  locked: "Desbloqueie a Ledger digitando o PIN nos botões físicos do dispositivo.",
  wrong_app: "Abra o app Ethereum na Ledger.",
};

export function ConnectLedger() {
  const [polling, setPolling] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [status, setStatus] = useState("not_connected");
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  function startPolling() {
    setAddress(null);
    setStatus("not_connected");
    setPolling(true);

    intervalRef.current = setInterval(async () => {
      try {
        const found = await invoke<string>("get_ledger_address");
        if (intervalRef.current) clearInterval(intervalRef.current);
        setAddress(found);
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

  if (address) {
    return (
      <p className="muted">
        Ledger conectada: <code className="address">{address}</code>
      </p>
    );
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

  return <button onClick={startPolling}>Conectar Ledger</button>;
}

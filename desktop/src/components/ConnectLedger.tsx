import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { ledger, setLedgerAccountIndex } from "../connectors/ledger";

// Mensagem mostrada conforme o rótulo de erro que o comando Rust devolve
// (ver classify_error em desktop/src-tauri/src/ledger.rs).
const INSTRUCTIONS: Record<string, string> = {
  not_connected: "Connect your Ledger via USB.",
  locked: "Unlock your Ledger by entering the PIN using the physical buttons.",
  wrong_app: "Open the Ethereum app on your Ledger.",
  // access_denied: device visible but could not open — on Windows may be a
  // conflict with Ledger Live; on Linux, missing udev rule.
  access_denied: "Could not access the Ledger. Close Ledger Live if it is open, or check USB permissions (Linux: udev rule).",
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
          {INSTRUCTIONS[status] ?? `Waiting for Ledger... (${status})`}
        </p>
        <button onClick={cancelPolling}>Cancel</button>
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
          <option key={i} value={i}>Account {i}</option>
        ))}
      </select>
      <button onClick={startPolling}>Connect Ledger</button>
    </div>
  );
}

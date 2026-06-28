import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { ledger, setLedgerAccountIndex } from "../connectors/ledger";

type LedgerPhase = "detecting" | "account-select";

// Maps the error string from Rust's classify_error to which step is active
function statusToStep(status: string): number {
  if (status === "locked") return 1;
  if (status === "wrong_app") return 2;
  return 0; // not_connected or anything else
}

const STEP_LABELS = [
  "Connect your Ledger via USB",
  "Unlock with your PIN on the device",
  "Open the Ethereum app on your Ledger",
];

export function ConnectLedger({ onBack }: { onBack: () => void }) {
  const { connectAsync } = useConnect();
  const [phase, setPhase] = useState<LedgerPhase>("detecting");
  const [status, setStatus] = useState("not_connected");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [isConnecting, setIsConnecting] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Start polling on mount
  useEffect(() => {
    intervalRef.current = setInterval(async () => {
      try {
        await invoke<string>("get_ledger_address", { accountIndex: 0 });
        clearInterval(intervalRef.current!);
        setPhase("account-select");
      } catch (e) {
        setStatus(String(e));
      }
    }, 1000);

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  function handleBack() {
    if (intervalRef.current) clearInterval(intervalRef.current);
    onBack();
  }

  async function handleConnect() {
    setIsConnecting(true);
    setConnectError(null);
    try {
      setLedgerAccountIndex(selectedIndex);
      await connectAsync({ connector: ledger });
    } catch (e) {
      setIsConnecting(false);
      setConnectError(String(e));
    }
  }

  const activeStep = statusToStep(status);
  const isAccessDenied = status === "access_denied";

  return (
    <div className="ledger-connect">
      <button className="back-btn" onClick={handleBack}>
        ← Back
      </button>

      {phase === "detecting" && (
        <>
          <h2 className="ledger-connect-title">Connect your Ledger</h2>

          <div className="stepper">
            {STEP_LABELS.map((label, i) => {
              const state =
                i < activeStep ? "done" : i === activeStep ? "active" : "pending";
              return (
                <div key={i} className={`step step--${state}`}>
                  <div className="step-indicator">
                    {state === "done" ? "✓" : i + 1}
                  </div>
                  <span className="step-text">{label}</span>
                </div>
              );
            })}
          </div>

          {isAccessDenied && (
            <div className="ledger-error-box">
              Could not access the Ledger. Close Ledger Live if it is open, or check USB permissions (Linux: udev rule).
            </div>
          )}
        </>
      )}

      {phase === "account-select" && (
        <>
          <h2 className="ledger-connect-title">Select account</h2>

          <div className="account-list">
            {[0, 1, 2, 3, 4].map((i) => (
              <button
                key={i}
                className={`account-option${selectedIndex === i ? " account-option--selected" : ""}`}
                onClick={() => setSelectedIndex(i)}
                disabled={isConnecting}
              >
                <div className="account-radio" />
                Account {i}
              </button>
            ))}
          </div>

          {connectError && (
            <div className="ledger-error-box" style={{ marginBottom: "1rem" }}>
              {connectError}
            </div>
          )}

          <button onClick={handleConnect} disabled={isConnecting}>
            {isConnecting ? "Connecting..." : `Connect Account ${selectedIndex}`}
          </button>
        </>
      )}
    </div>
  );
}

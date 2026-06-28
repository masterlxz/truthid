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

const ACCOUNT_COUNT = 5;

export function ConnectLedger({ onBack }: { onBack: () => void }) {
  const { connectAsync } = useConnect();
  const [phase, setPhase] = useState<LedgerPhase>("detecting");
  const [status, setStatus] = useState("not_connected");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [isConnecting, setIsConnecting] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // null = still loading, string = resolved address
  const [addresses, setAddresses] = useState<(string | null)[]>(
    Array(ACCOUNT_COUNT).fill(null)
  );

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

  // When device is detected, fetch addresses for all accounts sequentially.
  // Sequential (not parallel) because the Ledger HID interface is serial —
  // concurrent APDUs would conflict on the device.
  useEffect(() => {
    if (phase !== "account-select") return;

    let cancelled = false;
    setAddresses(Array(ACCOUNT_COUNT).fill(null));

    (async () => {
      for (let i = 0; i < ACCOUNT_COUNT; i++) {
        if (cancelled) break;
        try {
          const addr = await invoke<string>("get_ledger_address", { accountIndex: i });
          if (!cancelled) {
            setAddresses((prev) => {
              const next = [...prev];
              next[i] = addr;
              return next;
            });
          }
        } catch {
          // If the device disconnects mid-fetch, stop silently.
          break;
        }
      }
    })();

    return () => { cancelled = true; };
  }, [phase]);

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
            {Array.from({ length: ACCOUNT_COUNT }, (_, i) => (
              <button
                key={i}
                className={`account-option${selectedIndex === i ? " account-option--selected" : ""}`}
                onClick={() => setSelectedIndex(i)}
                disabled={isConnecting}
              >
                <div className="account-radio" />
                <div className="account-option-info">
                  <span className="account-option-name">Account {i}</span>
                  {addresses[i] !== null ? (
                    <code className="account-option-address">
                      {addresses[i]!.slice(0, 6)}…{addresses[i]!.slice(-4)}
                    </code>
                  ) : (
                    <span className="account-option-loading">loading…</span>
                  )}
                </div>
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

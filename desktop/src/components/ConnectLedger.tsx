import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { ledger, setLedgerAccountIndex } from "../connectors/ledger";

type LedgerPhase = "detecting" | "account-select";

// Achado real: o polling de detecção, a listagem de contas e o connect em si
// competem pela mesma Ledger física — chamadas HID concorrentes travam o
// dispositivo sem erro nenhum (mesmo bug já visto e corrigido em
// CreateIdentity.tsx). `device.write()` no lado Rust também não tem timeout
// (só a leitura tem), então uma chamada travada trava o botão pra sempre sem
// jeito de tentar de novo. HID_TIMEOUT_MS dá um limite do lado do frontend
// pra sempre poder desistir e tentar de novo, mesmo que o lado Rust nunca
// retorne.
const HID_TIMEOUT_MS = 8_000;

function withTimeout<T>(promise: Promise<T>, ms: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

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

  // Garante no máximo 1 chamada HID em voo por vez a partir deste componente.
  const hidBusyRef = useRef(false);

  // null = still loading, string = resolved address
  const [addresses, setAddresses] = useState<(string | null)[]>(
    Array(ACCOUNT_COUNT).fill(null)
  );
  const [addressesLoading, setAddressesLoading] = useState(false);

  // Start polling on mount
  useEffect(() => {
    intervalRef.current = setInterval(async () => {
      if (hidBusyRef.current) return; // já tem uma chamada em voo — pula esta rodada
      hidBusyRef.current = true;
      try {
        await withTimeout(
          invoke<string>("get_ledger_address", { accountIndex: 0 }),
          HID_TIMEOUT_MS,
          "Ledger did not respond in time.",
        );
        clearInterval(intervalRef.current!);
        setPhase("account-select");
      } catch (e) {
        setStatus(String(e));
      } finally {
        hidBusyRef.current = false;
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
    setAddressesLoading(true);

    (async () => {
      for (let i = 0; i < ACCOUNT_COUNT; i++) {
        if (cancelled) break;
        if (hidBusyRef.current) continue;
        hidBusyRef.current = true;
        try {
          const addr = await withTimeout(
            invoke<string>("get_ledger_address", { accountIndex: i }),
            HID_TIMEOUT_MS,
            "Ledger did not respond in time.",
          );
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
        } finally {
          hidBusyRef.current = false;
        }
      }
      if (!cancelled) setAddressesLoading(false);
    })();

    return () => { cancelled = true; };
  }, [phase]);

  function handleBack() {
    if (intervalRef.current) clearInterval(intervalRef.current);
    onBack();
  }

  async function handleConnect() {
    if (hidBusyRef.current) return;
    hidBusyRef.current = true;
    setIsConnecting(true);
    setConnectError(null);
    try {
      setLedgerAccountIndex(selectedIndex);
      await withTimeout(
        connectAsync({ connector: ledger }),
        HID_TIMEOUT_MS,
        "Ledger did not respond in time. Make sure it's unlocked with the Ethereum app open, then try again.",
      );
    } catch (e) {
      setConnectError(String(e));
    } finally {
      setIsConnecting(false);
      hidBusyRef.current = false;
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

          <button onClick={handleConnect} disabled={isConnecting || addressesLoading}>
            {isConnecting ? "Connecting..." : `Connect Account ${selectedIndex}`}
          </button>
        </>
      )}
    </div>
  );
}

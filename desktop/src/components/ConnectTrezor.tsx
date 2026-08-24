import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { trezor, setTrezorAccountIndex } from "../connectors/trezor";

type TrezorPhase = "detecting" | "account-select";

// Mesmo achado real já documentado em ConnectLedger.tsx (polling, listagem de
// contas e connect competem pelo mesmo device físico): chamadas USB
// concorrentes travam o dispositivo sem erro nenhum. O transporte da Trezor
// (libusb/rusb) não tem timeout de leitura nenhum — pior que a Ledger, que
// pelo menos tem timeout na leitura — então essa proteção do lado frontend é
// ainda mais necessária aqui, não menos.
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

// Maps the error string from Rust's classify_error to which step is active.
// Diferente da Ledger, não existe passo "abrir app" — a Trezor não tem
// conceito de app separado por moeda, um único firmware cobre tudo.
function statusToStep(status: string): number {
  if (status === "locked") return 1;
  return 0; // not_connected or anything else
}

const STEP_KEYS = ["connectUsb", "unlockDevice"] as const;

const ACCOUNT_COUNT = 5;

export function ConnectTrezor({ onBack }: { onBack: () => void }) {
  const { t } = useTranslation();
  const { connectAsync } = useConnect();
  const [phase, setPhase] = useState<TrezorPhase>("detecting");
  const [status, setStatus] = useState("not_connected");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [isConnecting, setIsConnecting] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Garante no máximo 1 chamada USB em voo por vez a partir deste componente.
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
          invoke<string>("get_trezor_address", { accountIndex: 0 }),
          HID_TIMEOUT_MS,
          "Trezor did not respond in time.",
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
  // Sequential (not parallel) because the Trezor USB interface is serial —
  // concurrent requests would conflict on the device.
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
            invoke<string>("get_trezor_address", { accountIndex: i }),
            HID_TIMEOUT_MS,
            "Trezor did not respond in time.",
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
      setTrezorAccountIndex(selectedIndex);
      await withTimeout(
        connectAsync({ connector: trezor }),
        HID_TIMEOUT_MS,
        t("connectTrezor.connectTimeout"),
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
  const isNotInitialized = status === "not_initialized";

  return (
    <div className="trezor-connect">
      <button className="back-btn" onClick={handleBack}>
        ← {t("connectTrezor.back")}
      </button>

      {phase === "detecting" && (
        <>
          <h2 className="trezor-connect-title">{t("connectTrezor.title")}</h2>

          <div className="stepper">
            {STEP_KEYS.map((key, i) => {
              const state =
                i < activeStep ? "done" : i === activeStep ? "active" : "pending";
              return (
                <div key={i} className={`step step--${state}`}>
                  <div className="step-indicator">
                    {state === "done" ? "✓" : i + 1}
                  </div>
                  <span className="step-text">{t(`connectTrezor.steps.${key}`)}</span>
                </div>
              );
            })}
          </div>

          {isAccessDenied && (
            <div className="trezor-error-box">
              {t("connectTrezor.accessDenied")}
            </div>
          )}

          {isNotInitialized && (
            <div className="trezor-error-box">
              {t("connectTrezor.notInitialized")}
            </div>
          )}
        </>
      )}

      {phase === "account-select" && (
        <>
          <h2 className="trezor-connect-title">{t("connectTrezor.selectAccount")}</h2>

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
                  <span className="account-option-name">{t("connectTrezor.accountName", { index: i })}</span>
                  {addresses[i] !== null ? (
                    <code className="account-option-address">
                      {addresses[i]!.slice(0, 6)}…{addresses[i]!.slice(-4)}
                    </code>
                  ) : (
                    <span className="account-option-loading">{t("connectTrezor.loading")}</span>
                  )}
                </div>
              </button>
            ))}
          </div>

          {connectError && (
            <div className="trezor-error-box" style={{ marginBottom: "1rem" }}>
              {connectError}
            </div>
          )}

          <button onClick={handleConnect} disabled={isConnecting || addressesLoading}>
            {isConnecting ? t("connectTrezor.connecting") : t("connectTrezor.connectAccount", { index: selectedIndex })}
          </button>
        </>
      )}
    </div>
  );
}

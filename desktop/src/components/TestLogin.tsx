import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { keccak256, toHex } from "viem";
import { SESSION_REGISTRY_ADDRESS, SESSION_REGISTRY_ABI } from "../config/contracts";

type LoginStatus = "idle" | "loading" | "success" | "error";
type SessionStatus = "idle" | "signing" | "pending" | "confirmed" | "error";

export function TestLogin() {
  const [serverUrl, setServerUrl] = useState("http://localhost:3000");
  const [loginStatus, setLoginStatus] = useState<LoginStatus>("idle");
  const [loginResult, setLoginResult] = useState<{
    token: string;
    identityId: string;
    deviceAddress: string;
    nonce: string;
  } | null>(null);
  const [loginError, setLoginError] = useState<string | null>(null);

  const [sessionHash, setSessionHash] = useState<`0x${string}` | null>(null);
  const [sessionStatus, setSessionStatus] = useState<SessionStatus>("idle");
  const [sessionError, setSessionError] = useState<string | null>(null);

  const {
    writeContract,
    data: createTxHash,
    isPending: isWritePending,
    error: writeError,
    reset: resetWrite,
  } = useWriteContract();

  const { isLoading: isCreateConfirming, isSuccess: isCreateSuccess } =
    useWaitForTransactionReceipt({ hash: createTxHash });

  useEffect(() => {
    if (isCreateSuccess) setSessionStatus("confirmed");
  }, [isCreateSuccess]);

  useEffect(() => {
    if (writeError) {
      setSessionStatus("error");
      setSessionError(writeError.message.split("\n")[0]);
    }
  }, [writeError]);

  async function handleLogin() {
    setLoginStatus("loading");
    setLoginError(null);
    setLoginResult(null);
    setSessionHash(null);
    setSessionStatus("idle");
    setSessionError(null);
    resetWrite();
    try {
      const res = await fetch(`${serverUrl}/auth/challenge`);
      if (!res.ok) throw new Error(`Server error: ${res.status}`);
      const { challenge } = await res.json();

      const deviceAddress = await invoke<string>("get_or_create_device_key");

      const message = JSON.stringify({
        type: challenge.type,
        nonce: challenge.nonce,
        issuedAt: challenge.issuedAt,
        origin: challenge.origin,
      });
      const signature = await invoke<string>("sign_challenge", { challenge: message });

      const verifyRes = await fetch(`${serverUrl}/auth/verify`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ approved: true, nonce: challenge.nonce, signature, deviceAddress }),
      });
      const verifyData = await verifyRes.json();
      if (!verifyRes.ok) throw new Error(verifyData.error ?? "Verification failed");

      setLoginResult({ ...verifyData, deviceAddress, nonce: challenge.nonce });
      setLoginStatus("success");
    } catch (e) {
      setLoginStatus("error");
      setLoginError(String(e));
    }
  }

  async function handleCreateSession() {
    if (!loginResult) return;
    setSessionStatus("signing");
    setSessionError(null);
    try {
      // Derive a unique 32-byte hash from the challenge nonce
      const hash = keccak256(toHex(loginResult.nonce)) as `0x${string}`;
      setSessionHash(hash);

      // Sign the session hash with the device key — contract verifies ecrecover
      const [r, s, v] = await invoke<[string, string, number]>("sign_session_hash", { hash });

      setSessionStatus("pending");
      writeContract({
        address: SESSION_REGISTRY_ADDRESS,
        abi: SESSION_REGISTRY_ABI,
        functionName: "createSession",
        args: [
          hash,
          BigInt(loginResult.identityId),
          loginResult.deviceAddress as `0x${string}`,
          r as `0x${string}`,
          s as `0x${string}`,
          v,
        ],
      });
    } catch (e) {
      setSessionStatus("error");
      setSessionError(String(e));
    }
  }

  const isLoginBusy = loginStatus === "loading";
  const isSessionBusy = sessionStatus === "signing" || sessionStatus === "pending" || isWritePending || isCreateConfirming;

  return (
    <div>
      {/* ── Step 1: Login ── */}
      <div className="card">
        <h3 style={{ marginTop: 0 }}>Step 1 — Authenticate</h3>
        <p className="muted">
          Signs a server challenge with this desktop's device key and verifies on-chain.
        </p>
        <div className="field">
          <label>Server URL</label>
          <input
            value={serverUrl}
            onChange={(e) => setServerUrl(e.target.value)}
            disabled={isLoginBusy}
            placeholder="http://localhost:3000"
          />
        </div>
        <div className="actions-row">
          <button onClick={handleLogin} disabled={isLoginBusy}>
            {isLoginBusy ? "Authenticating..." : "Test Login"}
          </button>
        </div>
        {loginStatus === "success" && loginResult && (
          <pre style={{
            marginTop: "0.75rem",
            background: "#0d2a1f",
            color: "#4ade80",
            padding: "0.75rem",
            borderRadius: "6px",
            fontSize: "0.85em",
            overflowX: "auto",
          }}>
            {JSON.stringify({ token: loginResult.token, identityId: loginResult.identityId }, null, 2)}
          </pre>
        )}
        {loginStatus === "error" && (
          <p className="error-text" style={{ marginTop: "0.5rem" }}>{loginError}</p>
        )}
      </div>

      {/* ── Step 2: Register session on-chain ── */}
      {loginStatus === "success" && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Step 2 — Register session on-chain</h3>
          <p className="muted">
            Creates an auditable record in the <code>SessionRegistry</code> contract. The device signs
            the session hash; the wallet submits the transaction.
          </p>
          <div className="actions-row">
            <button
              onClick={handleCreateSession}
              disabled={isSessionBusy || sessionStatus === "confirmed"}
            >
              {sessionStatus === "signing"
                ? "Signing..."
                : sessionStatus === "pending" || isWritePending
                ? "Confirm in wallet..."
                : isCreateConfirming
                ? "Waiting for network..."
                : sessionStatus === "confirmed"
                ? "✓ Session registered"
                : "Register session on-chain"}
            </button>
          </div>

          {sessionStatus === "confirmed" && sessionHash && (
            <div style={{ marginTop: "0.75rem" }}>
              <pre style={{
                background: "#0d2a1f",
                color: "#4ade80",
                padding: "0.75rem",
                borderRadius: "6px",
                fontSize: "0.85em",
                overflowX: "auto",
              }}>
                {JSON.stringify({ sessionHash }, null, 2)}
              </pre>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                Navigate to <strong>Active sessions</strong> to view and revoke this session.
              </p>
            </div>
          )}

          {sessionStatus === "error" && (
            <p className="error-text" style={{ marginTop: "0.5rem" }}>{sessionError}</p>
          )}
        </div>
      )}
    </div>
  );
}

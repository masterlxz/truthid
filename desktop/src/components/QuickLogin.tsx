import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { keccak256, toHex } from "viem";
import { SESSION_REGISTRY_ADDRESS, SESSION_REGISTRY_ABI } from "../config/contracts";

type LoginStatus = "idle" | "loading" | "success" | "error";
type SessionStatus = "idle" | "signing" | "pending" | "confirmed" | "error";

export function QuickLogin() {
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
      const hash = keccak256(toHex(loginResult.nonce)) as `0x${string}`;
      setSessionHash(hash);

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
  const isSessionBusy =
    sessionStatus === "signing" || sessionStatus === "pending" || isWritePending || isCreateConfirming;

  return (
    <div>
      <div className="field">
        <label>Server URL</label>
        <input
          value={serverUrl}
          onChange={(e) => setServerUrl(e.target.value)}
          disabled={isLoginBusy}
          placeholder="http://localhost:3000"
        />
      </div>

      <div className="actions-row" style={{ marginTop: 0, marginBottom: "1rem" }}>
        <button onClick={handleLogin} disabled={isLoginBusy}>
          {isLoginBusy ? "Authenticating..." : "Authenticate"}
        </button>
      </div>

      {loginStatus === "success" && loginResult && (
        <div className="card" style={{ marginBottom: "1rem" }}>
          <span className="status-badge status-badge--active" style={{ marginBottom: "0.5rem", display: "inline-flex" }}>
            ✓ Authenticated
          </span>
          <p className="muted" style={{ margin: "0.4rem 0 0" }}>
            Identity #{loginResult.identityId} · Token{" "}
            <code className="address">{loginResult.token.slice(0, 8)}…</code>
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
            <p className="muted" style={{ marginTop: "0.5rem", marginBottom: 0 }}>
              Session{" "}
              <code className="address">
                {sessionHash.slice(0, 10)}…{sessionHash.slice(-6)}
              </code>{" "}
              registered. Check Active Sessions to revoke.
            </p>
          )}

          {sessionStatus === "error" && sessionError && (
            <p className="error-text" style={{ marginTop: "0.5rem", marginBottom: 0 }}>
              {sessionError}
            </p>
          )}
        </div>
      )}

      {loginStatus === "error" && loginError && (
        <p className="error-text">{loginError}</p>
      )}
    </div>
  );
}

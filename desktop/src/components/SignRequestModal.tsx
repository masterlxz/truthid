import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { Address } from "viem";
import { decodeFunctionData, formatEther, parseAbi, toFunctionSelector } from "viem";
import { useIncomingSignRequest, type IncomingSignRequest } from "../hooks/useIncomingSignRequest";
import { executeViaUserOp } from "../services/userOpExecutor";
import { useWalletModal } from "../contexts/WalletModalContext";

interface BundlerConfig {
  api_key: string;
  network: string;
}

type DecodedCall =
  | { verified: true; functionName: string; args: readonly unknown[] }
  | { verified: false; reason: string };

/**
 * O TruthID nunca confia cegamente na `functionSignature` que o app terceiro
 * manda — recalcula o seletor (primeiros 4 bytes do keccak256 da assinatura,
 * via viem) e confere que bate com o callData recebido antes de decodificar.
 * Se não bater (ou a assinatura for inválida), a UI mostra os bytes crus +
 * um aviso em vez de bloquear — a aprovação humana é o ponto de confiança
 * final, não uma checagem no Rust (ver PROJECT_STATE.md, fatia 2b).
 */
function decodeIncomingCall(req: IncomingSignRequest): DecodedCall {
  try {
    const expectedSelector = toFunctionSelector(req.functionSignature);
    const actualSelector = req.callData.slice(0, 10);
    if (expectedSelector !== actualSelector) {
      return { verified: false, reason: "declared function signature does not match callData" };
    }
    // `as string` widens away the template-literal type TS would otherwise
    // infer here — viem's parseAbi does compile-time grammar validation on
    // literal signature strings, which fails oddly on a runtime-only value
    // like req.functionSignature (not a bug in the signature itself).
    const signature = `function ${req.functionSignature}` as string;
    const { functionName, args } = decodeFunctionData({
      abi: parseAbi([signature]),
      data: req.callData,
    });
    return { verified: true, functionName, args: args ?? [] };
  } catch (e) {
    return { verified: false, reason: String(e) };
  }
}

export function SignRequestModal({ smartAccountAddress }: { smartAccountAddress: Address | null }) {
  const { request, clear } = useIncomingSignRequest();
  const { openConnectModal } = useWalletModal();
  const [stage, setStage] = useState<"idle" | "signing" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const [expired, setExpired] = useState(false);

  // Failsafe local: o Rust já libera o pedido sozinho aos 5min (408 pro app
  // terceiro), isso só fecha o modal de quem ficou olhando a tela — não
  // depende disso pra segurança.
  useEffect(() => {
    if (!request) { setExpired(false); setStage("idle"); setError(null); return; }
    setExpired(Date.now() > request.expiresAtMs);
    const timer = setInterval(() => {
      if (Date.now() > request.expiresAtMs) {
        setExpired(true);
        clearInterval(timer);
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [request]);

  if (!request) return null;

  const decoded = decodeIncomingCall(request);
  const valueEth = (() => {
    try {
      return formatEther(BigInt(request.value || "0"));
    } catch {
      return request.value;
    }
  })();

  async function handleApprove() {
    if (!request) return;
    if (!smartAccountAddress) {
      // Não resolve o pedido — a wallet só não está conectada ainda, o
      // usuário pode tentar Approve de novo depois de conectar, o mesmo
      // pedido continua pendurado no Rust esperando.
      openConnectModal();
      return;
    }
    setStage("signing");
    setError(null);
    try {
      const bundlerConfig = await invoke<BundlerConfig>("get_bundler_config");
      if (!bundlerConfig.api_key) {
        throw new Error("Bundler not configured — set api_key/network in ~/.truthid/bundler_config.json.");
      }

      const { userOpHash, transactionHash } = await executeViaUserOp({
        smartAccountAddress,
        dest: request.dest,
        value: BigInt(request.value || "0"),
        callData: request.callData,
        bundlerApiKey: bundlerConfig.api_key,
        bundlerNetwork: bundlerConfig.network || "base",
      });

      await invoke("respond_to_sign_request", {
        id: request.id,
        decision: { outcome: "executed", userOpHash, transactionHash },
      });
      clear();
    } catch (e) {
      const message = String(e);
      setError(message);
      setStage("error");
      await invoke("respond_to_sign_request", {
        id: request.id,
        decision: { outcome: "failed", error: message },
      }).catch(() => {});
    }
  }

  async function handleReject() {
    if (!request) return;
    await invoke("respond_to_sign_request", {
      id: request.id,
      decision: { outcome: "rejected" },
    }).catch(() => {});
    clear();
  }

  const busy = stage === "signing";

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">Sign request</h2>
        </div>

        <div className="card">
          <p>
            <strong>{request.appName || "An app"}</strong> wants to call a function on your
            smart account.
          </p>

          {decoded.verified ? (
            <code className="address" style={{ display: "block", marginTop: "0.5rem" }}>
              {decoded.functionName}({decoded.args.map((a) => String(a)).join(", ")})
            </code>
          ) : (
            <>
              <span className="status-badge status-badge--revoked">
                ⚠ Could not verify declared function ({decoded.reason})
              </span>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                App claims this function (unverified — does not match callData):
              </p>
              <code className="address" style={{ display: "block" }}>
                {request.functionSignature}
              </code>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                Raw call data:
              </p>
              <code className="address" style={{ display: "block" }}>
                {request.callData}
              </code>
            </>
          )}

          <p className="muted" style={{ marginTop: "0.75rem" }}>
            Contract: <code>{request.dest}</code>
            <br />
            Value: {valueEth} ETH
          </p>

          {expired && <p className="error-text">This request has expired.</p>}
          {error && <p className="error-text">{error}</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleApprove} disabled={busy || expired}>
              {busy ? "Signing..." : "Approve"}
            </button>
            <button onClick={handleReject} disabled={busy} className="topbar-btn-danger">
              Reject
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

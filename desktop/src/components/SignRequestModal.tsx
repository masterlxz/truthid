import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import type { Address } from "viem";
import { decodeFunctionData, formatEther, parseAbi, toFunctionSelector } from "viem";
import { useIncomingSignRequest, type IncomingSignRequest } from "../hooks/useIncomingSignRequest";
import { useRequestExpiry } from "../hooks/useRequestExpiry";
import { executeViaUserOp } from "../services/userOpExecutor";
import { respondToRequest } from "../services/respondToRequest";
import { useWalletModal } from "../contexts/WalletModalContext";

type DecodedCall =
  | { verified: true; functionName: string; args: readonly unknown[] }
  | { verified: false; reason: string };

/**
 * O TruthID nunca confia cegamente na `functionSignature` que o app terceiro
 * manda — recalcula o seletor (primeiros 4 bytes do keccak256 da assinatura,
 * via viem) e confere que bate com o callData recebido antes de decodificar.
 * Se não bater (ou a assinatura for inválida), a UI mostra os bytes crus +
 * um aviso em vez de bloquear — a aprovação humana é o ponto de confiança
 * final, não uma checagem no Rust (ver project/INDEX.md, fatia 2b).
 */
function decodeIncomingCall(req: IncomingSignRequest): DecodedCall {
  try {
    const expectedSelector = toFunctionSelector(req.functionSignature);
    const actualSelector = req.callData.slice(0, 10).toLowerCase();
    if (expectedSelector !== actualSelector) {
      // Marcador resolvido pro texto localizado no componente (esta função
      // roda fora de um componente React, sem acesso a `useTranslation()`) —
      // diferente de `String(e)` no catch abaixo, que é mensagem de erro
      // crua e não precisa (nem dá) de tradução.
      return { verified: false, reason: "signature_mismatch" };
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
  const { t } = useTranslation();
  const { request, clear } = useIncomingSignRequest();
  const { openConnectModal } = useWalletModal();
  const [stage, setStage] = useState<"idle" | "signing" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const expired = useRequestExpiry(request?.expiresAtMs ?? null);

  // Quando o pedido muda (novo ou cancelado), reseta o estado do modal.
  useEffect(() => {
    if (!request) { setStage("idle"); setError(null); }
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
      openConnectModal();
      return;
    }

    // Checa expiração local antes de gastar gas — cobre o caso do
    // setInterval não ter disparado (janela minimizada, webview throttle).
    if (Date.now() > request.expiresAtMs) {
      setError(t("signRequestModal.requestExpiredNoUserOp"));
      setStage("idle");
      return;
    }

    // Checa no Rust se o pedido ainda está pendente (não expirou no lado
    // servidor). Fonte da verdade, já que o timeout de 300s é server-side.
    const stillValid = await invoke<boolean>("check_sign_request_valid", {
      id: request.id,
    });
    if (!stillValid) {
      setError(t("signRequestModal.requestExpiredNoUserOp"));
      setStage("idle");
      return;
    }

    setStage("signing");
    setError(null);
    try {
      const { userOpHash, transactionHash, success } = await executeViaUserOp({
        smartAccountAddress,
        dest: request.dest,
        value: BigInt(request.value || "0"),
        callData: request.callData,
      });

      if (!transactionHash) {
        throw new Error(t("signRequestModal.userOpNotConfirmed"));
      }

      await invoke("respond_to_sign_request", {
        id: request.id,
        decision: { outcome: success ? "executed" : "failed", userOpHash, transactionHash },
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
    respondToRequest("respond_to_sign_request", request.id, clear);
  }

  const busy = stage === "signing";
  const reasonText =
    !decoded.verified && decoded.reason === "signature_mismatch"
      ? t("signRequestModal.signatureMismatchReason")
      : !decoded.verified
      ? decoded.reason
      : "";

  return (
    <div className="modal-overlay">
      <div className="modal-box">
        <div className="modal-header">
          <h2 className="modal-title">{t("signRequestModal.title")}</h2>
        </div>

        <div className="card">
          <p>
            <strong>{request.appName || t("signRequestModal.defaultAppName")}</strong>{" "}
            {t("signRequestModal.wantsToCall")}
          </p>

          {decoded.verified ? (
            <code className="address" style={{ display: "block", marginTop: "0.5rem" }}>
              {decoded.functionName}({decoded.args.map((a) => String(a)).join(", ")})
            </code>
          ) : (
            <>
              <span className="status-badge status-badge--revoked">
                {t("signRequestModal.couldNotVerify", { reason: reasonText })}
              </span>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                {t("signRequestModal.unverifiedClaim")}
              </p>
              <code className="address" style={{ display: "block" }}>
                {request.functionSignature}
              </code>
              <p className="muted" style={{ marginTop: "0.5rem" }}>
                {t("signRequestModal.rawCallData")}
              </p>
              <code className="address" style={{ display: "block" }}>
                {request.callData}
              </code>
            </>
          )}

          <p className="muted" style={{ marginTop: "0.75rem" }}>
            {t("signRequestModal.contractLabel")} <code>{request.dest}</code>
            <br />
            {t("signRequestModal.valueLine", { value: valueEth })}
          </p>

          {expired && <p className="error-text">{t("signRequestModal.requestExpired")}</p>}
          {error && <p className="error-text">{error}</p>}

          <div className="actions-row" style={{ marginTop: "0.75rem" }}>
            <button onClick={handleApprove} disabled={busy || expired}>
              {busy ? t("signRequestModal.signing") : t("signRequestModal.approve")}
            </button>
            <button onClick={handleReject} disabled={busy} className="topbar-btn-danger">
              {t("signRequestModal.reject")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

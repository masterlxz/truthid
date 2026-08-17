import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { useQueryClient } from "@tanstack/react-query";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { type Address, formatEther, parseEther, isAddress } from "viem";
import { TRUTHID_ACCOUNT_ABI } from "../config/contracts";
import { useWalletModal } from "../contexts/WalletModalContext";

export function WithdrawModal({
  smartAccountAddress,
  availableBalance,
  onClose,
}: {
  smartAccountAddress: Address;
  availableBalance: bigint;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  const { isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();
  const queryClient = useQueryClient();

  const [destination, setDestination] = useState("");
  const [amount, setAmount] = useState("");
  const [step, setStep] = useState<"form" | "confirming" | "done">("form");

  const {
    writeContract,
    data: txHash,
    isPending,
    isError,
    error,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // Guard contra disparo duplicado — mesmo idioma de CreateIdentity.tsx:
  // `isPending` do React Query não atualiza no mesmo tick da chamada, então
  // um efeito repetido rápido pode disparar 2 chamadas HID concorrentes e
  // travar a Ledger sem erro nenhum.
  const txSubmitted = useRef(false);

  useEffect(() => {
    if (
      step === "confirming" &&
      !txHash &&
      !isPending &&
      !isConfirming &&
      !txSubmitted.current
    ) {
      txSubmitted.current = true;
      writeContract({
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "execute",
        args: [destination as Address, parseEther(amount), "0x"],
      });
    }
  }, [step, txHash, isPending, isConfirming, writeContract, smartAccountAddress, destination, amount]);

  useEffect(() => {
    if (isSuccess) {
      setStep("done");
      queryClient.invalidateQueries();
    }
  }, [isSuccess, queryClient]);

  const addressIsValid = destination.length === 0 || isAddress(destination);

  const parsedAmount = (() => {
    try {
      return parseEther(amount);
    } catch {
      return null;
    }
  })();
  const amountIsValid = parsedAmount !== null && parsedAmount > 0n && parsedAmount <= availableBalance;
  const amountError =
    amount.length === 0
      ? null
      : parsedAmount === null || parsedAmount <= 0n
      ? t("withdrawModal.invalidEthAmount")
      : parsedAmount > availableBalance
      ? t("withdrawModal.amountExceedsBalance")
      : null;

  const canSubmit = step === "form" && isAddress(destination) && amountIsValid;

  function handleMax() {
    setAmount(formatEther(availableBalance));
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!isConnected) {
      openConnectModal();
      return;
    }
    if (!canSubmit) return;
    setStep("confirming");
  }

  if (step === "done") {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("withdrawModal.withdrawalSent")}</p>
        <p>
          {t("withdrawModal.sentSummary", { amount })} <code className="address">{destination}</code>
        </p>
        <div className="actions-row">
          <button onClick={onClose}>{t("withdrawModal.close")}</button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="card">
      <h3 style={{ marginTop: 0 }}>{t("withdrawModal.title")}</h3>

      <div className="field">
        <label>{t("withdrawModal.destinationLabel")}</label>
        <input
          value={destination}
          onChange={(e) => setDestination(e.target.value.trim())}
          placeholder="0x..."
          disabled={step !== "form"}
          style={{ fontFamily: "monospace" }}
        />
        {!addressIsValid && <p className="error-text">{t("withdrawModal.invalidAddress")}</p>}
      </div>

      <div className="field">
        <label>{t("withdrawModal.amountLabel")}</label>
        <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
          <input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.0"
            disabled={step !== "form"}
            style={{ width: "8rem" }}
          />
          <button type="button" onClick={handleMax} disabled={step !== "form"}>
            {t("withdrawModal.max")}
          </button>
        </div>
        <p className="muted" style={{ fontSize: "0.85rem" }}>
          {t("withdrawModal.available", { amount: formatEther(availableBalance) })}
        </p>
        {amountError && <p className="error-text">{amountError}</p>}
      </div>

      {isError && (
        <p className="error-text">
          {error?.message?.includes("rejected_by_user")
            ? t("withdrawModal.rejectedOnLedger")
            : t("withdrawModal.errorPrefix", { message: error?.message?.split("\n")[0] ?? "operation failed" })}
        </p>
      )}

      <div className="actions-row">
        {step === "form" && (
          <button type="submit" disabled={!canSubmit}>
            {t("withdrawModal.withdraw")}
          </button>
        )}
        {step === "confirming" && (
          <button type="button" disabled>
            {isPending
              ? t("withdrawModal.confirmInWallet")
              : isConfirming
              ? t("withdrawModal.waitingForConfirmation")
              : t("withdrawModal.confirming")}
          </button>
        )}
        <button type="button" onClick={onClose} disabled={step === "confirming"}>
          {t("withdrawModal.cancel")}
        </button>
      </div>
    </form>
  );
}

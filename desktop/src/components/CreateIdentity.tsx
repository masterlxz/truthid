import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSendTransaction,
} from "wagmi";
import { type Address, parseEther } from "viem";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  FACTORY_ADDRESS,
  FACTORY_ABI,
} from "../config/contracts";

const USERNAME_REGEX = /^[a-z0-9.\-]{1,64}$/;

const DEFAULT_FUNDING_ETH = "0.001";

export function CreateIdentity({ smartAccountAddress }: { smartAccountAddress: Address }) {
  const [username, setUsername] = useState("");
  const [fundingEth, setFundingEth] = useState(DEFAULT_FUNDING_ETH);
  const [step, setStep] = useState<0 | 1 | 2 | 3>(0);
  const { address } = useAccount();

  const queryClient = useQueryClient();

  const { data: existingUsername } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: [smartAccountAddress],
  });

  const { data: isTaken } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "isUsernameTaken",
    args: [username],
    query: { enabled: username.length > 0 },
  });

  const {
    writeContract: createIdentity,
    data: tx1Hash,
    isPending: tx1Pending,
    isError: tx1Error,
    error: tx1Err,
  } = useWriteContract();

  const {
    isLoading: tx1Confirming,
    isSuccess: tx1Success,
  } = useWaitForTransactionReceipt({ hash: tx1Hash });

  const {
    writeContract: deployAccount,
    data: tx2Hash,
    isPending: tx2Pending,
    isError: tx2Error,
    error: tx2Err,
  } = useWriteContract();

  const {
    isLoading: tx2Confirming,
    isSuccess: tx2Success,
  } = useWaitForTransactionReceipt({ hash: tx2Hash });

  const {
    sendTransaction: fundAccount,
    data: tx3Hash,
    isPending: tx3Pending,
    isError: tx3Error,
    error: tx3Err,
  } = useSendTransaction();

  const {
    isLoading: tx3Confirming,
    isSuccess: tx3Success,
  } = useWaitForTransactionReceipt({ hash: tx3Hash });

  const overallError = tx1Err ?? tx2Err ?? tx3Err;
  const hasError = tx1Error || tx2Error || tx3Error;

  useEffect(() => {
    if (tx1Success) setStep(2);
  }, [tx1Success]);

  useEffect(() => {
    if (tx2Success) setStep(3);
  }, [tx2Success]);

  useEffect(() => {
    if (tx3Success || tx1Success) queryClient.invalidateQueries();
  }, [tx3Success, tx1Success, queryClient]);

  useEffect(() => {
    if (tx1Success && step === 2 && !tx2Hash && !tx2Pending && !tx2Confirming) {
      deployAccount({
        address: FACTORY_ADDRESS,
        abi: FACTORY_ABI,
        functionName: "createAccount",
        args: [address!],
      });
    }
  }, [tx1Success, step, tx2Hash, tx2Pending, tx2Confirming, deployAccount, address]);

  useEffect(() => {
    if (tx2Success && step === 3 && !tx3Hash && !tx3Pending && !tx3Confirming) {
      const value = (() => {
        try {
          return parseEther(fundingEth);
        } catch {
          return parseEther(DEFAULT_FUNDING_ETH);
        }
      })();
      fundAccount({ to: smartAccountAddress, value });
    }
  }, [tx2Success, step, tx3Hash, tx3Pending, tx3Confirming, fundAccount, smartAccountAddress, fundingEth]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStep(1);
    createIdentity({
      address: IDENTITY_REGISTRY_ADDRESS,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "createIdentity",
      args: [username, smartAccountAddress],
    });
  }

  const isValidFormat = USERNAME_REGEX.test(username);
  const isFundingValid = (() => {
    try {
      return parseEther(fundingEth) > 0n;
    } catch {
      return false;
    }
  })();

  const isFormPending = tx1Pending || tx1Confirming || tx2Pending || tx2Confirming || tx3Pending || tx3Confirming;
  const canSubmit = step === 0 && isValidFormat && !isTaken && !isFormPending && isFundingValid;

  if (existingUsername) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identity already registered:</p>
        <strong>@{existingUsername as string}</strong>
      </div>
    );
  }

  if (tx3Success) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identity created successfully!</p>
        <strong>@{username}</strong>
        <p className="muted" style={{ marginTop: "0.5rem" }}>
          Smart account funded with {fundingEth} ETH. Your Ledger will not be charged for future operations.
        </p>
      </div>
    );
  }

  const steps = [
    { num: 1, label: "Creating identity on-chain", active: step >= 1, done: step > 1 || tx1Success },
    { num: 2, label: "Deploying smart account", active: step >= 2, done: step > 2 || tx2Success },
    { num: 3, label: "Funding smart account", active: step >= 3, done: tx3Success },
  ];

  return (
    <form onSubmit={handleSubmit} className="card">
      <h2>Create identity</h2>

      <div className="field">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value.toLowerCase())}
          placeholder="choose a username"
          disabled={isFormPending}
        />
      </div>

      {username.length > 0 && !isValidFormat && (
        <p className="muted">Lowercase letters, numbers, dots and hyphens only (max. 64 characters)</p>
      )}

      {isValidFormat && isTaken && (
        <p className="muted">Username already taken</p>
      )}

      <div className="field" style={{ marginTop: "0.75rem" }}>
        <label className="muted" style={{ display: "block", marginBottom: "0.25rem", fontSize: "0.85rem" }}>
          Initial funding (ETH)
        </label>
        <input
          value={fundingEth}
          onChange={(e) => setFundingEth(e.target.value)}
          placeholder={DEFAULT_FUNDING_ETH}
          disabled={isFormPending}
          style={{ width: "8rem" }}
        />
      </div>

      {!isFundingValid && fundingEth.length > 0 && (
        <p className="muted">Enter a valid ETH amount</p>
      )}

      <div className="muted" style={{ marginTop: "0.75rem", fontSize: "0.85rem", lineHeight: "1.5" }}>
        This setup uses 3 transactions. Your Ledger pays gas one time only.
        After setup, your smart account pays its own gas for all future operations.
      </div>

      {step > 0 && (
        <div style={{ marginTop: "1rem" }}>
          {steps.map((s) => (
            <div
              key={s.num}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "0.5rem",
                padding: "0.25rem 0",
                opacity: s.active ? 1 : 0.4,
              }}
            >
              <span>{s.done ? "✓" : s.active ? "●" : "○"}</span>
              <span>{s.label}</span>
            </div>
          ))}
        </div>
      )}

      {hasError && (
        <p className="error-text" style={{ marginTop: "0.5rem" }}>
          {overallError?.message?.includes("rejected_by_user")
            ? "Transaction rejected on Ledger."
            : `Error: ${overallError?.message?.split("\n")[0] ?? "transaction failed"}`}
        </p>
      )}

      {step === 0 && (
        <button type="submit" disabled={!canSubmit}>
          Register identity
        </button>
      )}

      {step === 1 && (
        <button type="button" disabled>
          {tx1Pending ? "Confirm tx 1/3 in wallet..." : tx1Confirming ? "Waiting for confirmation..." : "Step 1/3"}
        </button>
      )}

      {step === 2 && (
        <button type="button" disabled>
          {tx2Pending ? "Confirm tx 2/3 in wallet..." : tx2Confirming ? "Waiting for confirmation..." : "Step 2/3"}
        </button>
      )}

      {step === 3 && (
        <button type="button" disabled>
          {tx3Pending ? "Confirm tx 3/3 in wallet..." : tx3Confirming ? "Waiting for confirmation..." : "Step 3/3"}
        </button>
      )}
    </form>
  );
}
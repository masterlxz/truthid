import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
} from "../config/contracts";

const USERNAME_REGEX = /^[a-z0-9.\-]{1,64}$/;

export function CreateIdentity() {
  const [username, setUsername] = useState("");
  const { address } = useAccount();

  // Leitura 1: essa wallet já tem uma identidade?
  const { data: existingUsername } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: [address!],
  });

  // Leitura 2: esse username já está em uso? (só consulta se tiver algo digitado)
  const { data: isTaken } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "isUsernameTaken",
    args: [username],
    query: { enabled: username.length > 0 },
  });

  const queryClient = useQueryClient();

  // Escrita: chamar createIdentity no contrato
  const { writeContract, data: txHash, isPending, isError: isWriteError, error: writeError } = useWriteContract();

  // Aguarda confirmação da transação na rede
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  // Força o App.tsx a reler getUsernameByController após confirmação
  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);

  const isError = isWriteError || isReceiptError;
  const error = writeError ?? receiptError;

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    // Por ora passa o endereço conectado como controller (comportamento idêntico
    // ao anterior). Na etapa 14.7 isso será substituído pelo endereço CREATE2
    // da smart account pré-computada.
    writeContract({
      address: IDENTITY_REGISTRY_ADDRESS,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "createIdentity",
      args: [username, address!],
    });
  }

  const isValidFormat = USERNAME_REGEX.test(username);
  const canSubmit = isValidFormat && !isTaken && !isPending && !isConfirming;

  // Wallet já tem identidade
  if (existingUsername) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identity already registered:</p>
        <strong>@{existingUsername}</strong>
      </div>
    );
  }

  // Transação confirmada na rede
  if (isSuccess) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identity created successfully!</p>
        <strong>@{username}</strong>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="card">
      <h2>Create identity</h2>

      <div className="field">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value.toLowerCase())}
          placeholder="choose a username"
          disabled={isPending || isConfirming}
        />
      </div>

      {username.length > 0 && !isValidFormat && (
        <p className="muted">Lowercase letters, numbers, dots and hyphens only (max. 64 characters)</p>
      )}

      {isValidFormat && isTaken && (
        <p className="muted">Username already taken</p>
      )}

      {isError && (
        <p className="error-text">
          {error?.message?.includes("rejected_by_user")
            ? "Transaction rejected on Ledger."
            : `Error: ${error?.message?.split("\n")[0] ?? "transaction failed"}`}
        </p>
      )}

      <button type="submit" disabled={!canSubmit}>
        {isPending
          ? "Confirm in wallet..."
          : isConfirming
          ? "Waiting for network confirmation..."
          : "Register identity"}
      </button>
    </form>
  );
}

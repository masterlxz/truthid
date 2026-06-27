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
    writeContract({
      address: IDENTITY_REGISTRY_ADDRESS,
      abi: IDENTITY_REGISTRY_ABI,
      functionName: "createIdentity",
      args: [username],
    });
  }

  const isValidFormat = USERNAME_REGEX.test(username);
  const canSubmit = isValidFormat && !isTaken && !isPending && !isConfirming;

  // Wallet já tem identidade
  if (existingUsername) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identidade já registrada:</p>
        <strong>@{existingUsername}</strong>
      </div>
    );
  }

  // Transação confirmada na rede
  if (isSuccess) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>Identidade criada com sucesso!</p>
        <strong>@{username}</strong>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="card">
      <h2>Criar identidade</h2>

      <div className="field">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value.toLowerCase())}
          placeholder="escolha um username"
          disabled={isPending || isConfirming}
        />
      </div>

      {username.length > 0 && !isValidFormat && (
        <p className="muted">Apenas letras minúsculas, números, ponto e hífen (máx. 64 caracteres)</p>
      )}

      {isValidFormat && isTaken && (
        <p className="muted">Username já está em uso</p>
      )}

      {isError && (
        <p className="error-text">
          {error?.message?.includes("rejected_by_user")
            ? "Transação rejeitada na Ledger."
            : `Erro: ${error?.message?.split("\n")[0] ?? "transação falhou"}`}
        </p>
      )}

      <button type="submit" disabled={!canSubmit}>
        {isPending
          ? "Confirme na carteira..."
          : isConfirming
          ? "Aguardando confirmação da rede..."
          : "Registrar identidade"}
      </button>
    </form>
  );
}

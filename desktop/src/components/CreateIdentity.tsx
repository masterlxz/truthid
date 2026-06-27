import { useState } from "react";
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

  // Escrita: chamar createIdentity no contrato
  const { writeContract, data: txHash, isPending } = useWriteContract();

  // Aguarda confirmação da transação na rede
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

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
      <div>
        <p>Identidade já registrada:</p>
        <strong>@{existingUsername}</strong>
      </div>
    );
  }

  // Transação confirmada na rede
  if (isSuccess) {
    return (
      <div>
        <p>Identidade criada com sucesso!</p>
        <strong>@{username}</strong>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit}>
      <h2>Criar identidade</h2>

      <input
        value={username}
        onChange={(e) => setUsername(e.target.value.toLowerCase())}
        placeholder="escolha um username"
        disabled={isPending || isConfirming}
      />

      {username.length > 0 && !isValidFormat && (
        <p>Apenas letras minúsculas, números, ponto e hífen (máx. 64 caracteres)</p>
      )}

      {isValidFormat && isTaken && (
        <p>Username já está em uso</p>
      )}

      <button type="submit" disabled={!canSubmit}>
        {isPending
          ? "Confirme no MetaMask..."
          : isConfirming
          ? "Aguardando confirmação da rede..."
          : "Registrar identidade"}
      </button>
    </form>
  );
}

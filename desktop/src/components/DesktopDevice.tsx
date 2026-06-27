import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { keccak256, encodePacked } from "viem";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI } from "../config/contracts";

// invoke() é a ponte entre React e Rust.
// Quando chamamos invoke("get_or_create_device_key"), o Tauri executa a
// função Rust correspondente e devolve o resultado para o JavaScript.
// É como uma API interna do app — sem servidor, sem rede.

export function DesktopDevice({ onRegistered }: { onRegistered: () => void }) {
  const [address, setAddress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { address: controllerAddress } = useAccount();
  const queryClient = useQueryClient();

  // Na primeira renderização, pede ao Rust para gerar/recuperar a chave do keyring
  useEffect(() => {
    invoke<string>("get_or_create_device_key")
      .then(setAddress)
      .catch((e) => setError(String(e)));
  }, []);

  // Consulta a blockchain: este desktop já está registrado como device?
  const { data: isActive, refetch } = useReadContract({
    address: DEVICE_REGISTRY_ADDRESS,
    abi: DEVICE_REGISTRY_ABI,
    functionName: "isDeviceActive",
    args: [address as `0x${string}`],
    query: { enabled: !!address },
  });

  // Registro em 2 passos (commit-reveal) — esconde o devicePubKey até a
  // confirmação. Sem isso, alguém observando a mempool poderia ver o
  // endereço do device pendente e registrá-lo primeiro para a própria
  // identidade (front-running — ver auditoria de segurança, achado #7).
  const [phase, setPhase] = useState<"idle" | "committing" | "registering">("idle");
  const [salt, setSalt] = useState<`0x${string}` | null>(null);

  const { writeContract: sendCommit, data: commitHash, isPending: isCommitPending, isError: isCommitError, error: commitError } = useWriteContract();
  const { writeContract: sendRegister, data: registerHash, isPending: isRegisterPending, isError: isRegisterError, error: registerError } = useWriteContract();

  const { isLoading: isCommitConfirming, isSuccess: isCommitSuccess } =
    useWaitForTransactionReceipt({ hash: commitHash });
  const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess } =
    useWaitForTransactionReceipt({ hash: registerHash });

  const isPending = isCommitPending || isRegisterPending;
  const isConfirming = isCommitConfirming || isRegisterConfirming;
  const writeError = commitError ?? registerError;
  const isWriteError = isCommitError || isRegisterError;

  useEffect(() => {
    if (!isCommitSuccess || phase !== "committing" || !address || !salt) return;
    setPhase("registering");
    // O contrato exige block.number > commitBlock (RevealTooEarly).
    // Base mina a cada ~2s, então 4s garante que estamos no próximo bloco.
    const timer = setTimeout(() => {
      sendRegister({
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "registerDevice",
        args: [address as `0x${string}`, "Este Desktop", salt],
      });
    }, 4000);
    return () => clearTimeout(timer);
  }, [isCommitSuccess]);

  useEffect(() => {
    if (!isRegisterSuccess || phase !== "registering") return;
    setPhase("idle");
    queryClient.invalidateQueries();
    refetch();
    onRegistered();
  }, [isRegisterSuccess]);

  function handleRegister() {
    if (!address || !controllerAddress) return;

    const saltBytes = crypto.getRandomValues(new Uint8Array(32));
    const newSalt = `0x${Array.from(saltBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}` as `0x${string}`;
    setSalt(newSalt);

    const commitment = keccak256(
      encodePacked(
        ["address", "bytes32", "address"],
        [address as `0x${string}`, newSalt, controllerAddress]
      )
    );

    setPhase("committing");
    sendCommit({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "commitDevice",
      args: [commitment],
    });
  }

  const isBusy = phase !== "idle";

  if (error) {
    return (
      <p className="error-text">
        Erro ao acessar o keyring do SO: {error}
      </p>
    );
  }

  if (!address) {
    return <p className="muted">Inicializando chave do desktop...</p>;
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>Este desktop</h3>
      <code className="address">
        {address.slice(0, 10)}…{address.slice(-6)}
      </code>
      <div style={{ marginTop: "0.75rem" }}>
        {isActive ? (
          <span className="status-badge status-badge--active">✓ Registrado como device</span>
        ) : (
          <>
            <span className="status-badge status-badge--revoked">Não registrado</span>
            {isWriteError && (
              <p className="error-text">
                {writeError?.message?.includes("rejected_by_user")
                  ? "Transação rejeitada na Ledger."
                  : `Erro: ${writeError?.message?.split("\n")[0]}`}
              </p>
            )}
            <div className="actions-row">
              <button onClick={handleRegister} disabled={isBusy}>
                {phase === "committing" && isPending
                  ? "Confirme na carteira (1/2)..."
                  : phase === "committing" && isConfirming
                  ? "Aguardando rede (1/2)..."
                  : phase === "registering" && isPending
                  ? "Confirme na carteira (2/2)..."
                  : phase === "registering" && isConfirming
                  ? "Aguardando rede (2/2)..."
                  : "Registrar este desktop"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

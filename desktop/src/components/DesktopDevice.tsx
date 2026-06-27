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
        args: [address as `0x${string}`, "This Desktop", salt],
      });
    }, 4000);
    return () => clearTimeout(timer);
  }, [isCommitSuccess]);

  useEffect(() => {
    if (!isRegisterSuccess || phase !== "registering") return;
    setPhase("idle");
    queryClient.invalidateQueries();
    // Wait for the RPC node to index the new block before refetching
    setTimeout(() => { refetch(); onRegistered(); }, 3000);
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
        Error accessing OS keyring: {error}
      </p>
    );
  }

  if (!address) {
    return <p className="muted">Initializing desktop key...</p>;
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>This desktop</h3>
      <code className="address">
        {address.slice(0, 10)}…{address.slice(-6)}
      </code>
      <div style={{ marginTop: "0.75rem" }}>
        {isActive ? (
          <span className="status-badge status-badge--active">✓ Registered as device</span>
        ) : (
          <>
            <span className="status-badge status-badge--revoked">Not registered</span>
            {isWriteError && (
              <p className="error-text">
                {writeError?.message?.includes("rejected_by_user")
                  ? "Transaction rejected on Ledger."
                  : `Error: ${writeError?.message?.split("\n")[0]}`}
              </p>
            )}
            <div className="actions-row">
              <button onClick={handleRegister} disabled={isBusy}>
                {phase === "committing" && isPending
                  ? "Confirm in wallet (1/2)..."
                  : phase === "committing" && isConfirming
                  ? "Waiting for network (1/2)..."
                  : phase === "registering" && isPending
                  ? "Confirm in wallet (2/2)..."
                  : phase === "registering" && isConfirming
                  ? "Waiting for network (2/2)..."
                  : "Register this desktop"}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

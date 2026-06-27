import { useEffect, useState } from "react";
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

  const { writeContract: sendTx, data: txHash, isPending } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (!isSuccess) return;

    if (phase === "committing" && address && salt) {
      // Commit confirmado — passo 2: revelar devicePubKey + salt
      setPhase("registering");
      sendTx({
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "registerDevice",
        args: [address as `0x${string}`, "Este Desktop", salt],
      });
    } else if (phase === "registering") {
      setPhase("idle");
      refetch();
      onRegistered();
    }
  }, [isSuccess]);

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
    sendTx({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "commitDevice",
      args: [commitment],
    });
  }

  const isBusy = phase !== "idle";

  if (error) {
    return (
      <p style={{ color: "red" }}>
        Erro ao acessar o keyring do SO: {error}
      </p>
    );
  }

  if (!address) {
    return <p>Inicializando chave do desktop...</p>;
  }

  return (
    <div style={{ marginTop: "1rem" }}>
      <h3>Este desktop</h3>
      <small style={{ fontFamily: "monospace" }}>
        {address.slice(0, 10)}…{address.slice(-6)}
      </small>
      <br />
      {isActive ? (
        <span>✅ Registrado como device</span>
      ) : (
        <>
          <span>⬜ Não registrado</span>
          <br />
          <button
            onClick={handleRegister}
            disabled={isBusy}
            style={{ marginTop: "0.5rem" }}
          >
            {phase === "committing" && isPending
              ? "Confirme no MetaMask (1/2)..."
              : phase === "committing" && isConfirming
              ? "Preparando registro (1/2)..."
              : phase === "registering" && isPending
              ? "Confirme no MetaMask (2/2)..."
              : phase === "registering" && isConfirming
              ? "Aguardando rede (2/2)..."
              : "Registrar este desktop"}
          </button>
        </>
      )}
    </div>
  );
}

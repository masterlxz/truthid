import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI } from "../config/contracts";

// invoke() é a ponte entre React e Rust.
// Quando chamamos invoke("get_or_create_device_key"), o Tauri executa a
// função Rust correspondente e devolve o resultado para o JavaScript.
// É como uma API interna do app — sem servidor, sem rede.

export function DesktopDevice({ onRegistered }: { onRegistered: () => void }) {
  const [address, setAddress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

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

  // Registra este desktop como device na blockchain
  const {
    writeContract: sendRegister,
    data: txHash,
    isPending,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (isSuccess) {
      refetch();
      onRegistered();
    }
  }, [isSuccess]);

  function handleRegister() {
    sendRegister({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "registerDevice",
      args: [address as `0x${string}`, "Este Desktop"],
    });
  }

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
            disabled={isPending || isConfirming}
            style={{ marginTop: "0.5rem" }}
          >
            {isPending
              ? "Confirme no MetaMask..."
              : isConfirming
              ? "Aguardando rede..."
              : "Registrar este desktop"}
          </button>
        </>
      )}
    </div>
  );
}

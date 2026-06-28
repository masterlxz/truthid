import { useEffect, useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { keccak256, encodePacked, isAddress } from "viem";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI } from "../config/contracts";
import { useWalletModal } from "../contexts/WalletModalContext";

// Este componente:
// 1. Mostra um campo pra colar o endereço que o celular exibe (tela "Mostrar
//    QR para parear" do app mobile — hoje sem leitura de câmera no desktop,
//    só colar; câmera pode ser adicionada depois como melhoria de UX)
// 2. Registra esse endereço na blockchain via commit-reveal (2 transações)
//
// Não existe troca de mensagem ao vivo com o celular — o celular já mostrou
// o endereço dele (não precisa de rede pra isso), e aqui só confirmamos a
// transação. O próprio celular detecta quando terminou fazendo polling
// on-chain (ver ShowDeviceQrScreen no mobile).

export function PairDevice({ onDeviceRegistered }: {
  onDeviceRegistered: () => void;
}) {
  const { address: controllerAddress, isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();

  const [isOpen, setIsOpen] = useState(false);
  const [addressInput, setAddressInput] = useState("");
  const [labelInput, setLabelInput] = useState("");

  // Registro em 2 passos (commit-reveal) — esconde o devicePubKey até a
  // confirmação, impedindo front-running (ver auditoria, achado #7).
  const [registerPhase, setRegisterPhase] = useState<"idle" | "committing" | "registering">("idle");
  const [salt, setSalt] = useState<`0x${string}` | null>(null);

  const {
    writeContract: sendCommit,
    data: commitTxHash,
    isPending: isCommitPending,
    isError: isCommitError,
    error: commitError,
  } = useWriteContract();

  const {
    writeContract: sendRegister,
    data: registerTxHash,
    isPending: isRegisterPending,
    isError: isRegisterError,
    error: registerError,
  } = useWriteContract();

  const { isLoading: isCommitConfirming, isSuccess: isCommitSuccess } =
    useWaitForTransactionReceipt({ hash: commitTxHash });
  const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess } =
    useWaitForTransactionReceipt({ hash: registerTxHash });

  const isRegisterPendingAny = isCommitPending || isRegisterPending;
  const isRegisterConfirmingAny = isCommitConfirming || isRegisterConfirming;
  const pairError = commitError ?? registerError;
  const isPairError = isCommitError || isRegisterError;

  useEffect(() => {
    if (!isCommitSuccess || registerPhase !== "committing" || !salt || !isAddress(addressInput)) return;
    setRegisterPhase("registering");
    const timer = setTimeout(() => {
      sendRegister({
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "registerDevice",
        args: [addressInput as `0x${string}`, labelInput, salt],
      });
    }, 4000);
    return () => clearTimeout(timer);
  }, [isCommitSuccess]);

  useEffect(() => {
    if (!isRegisterSuccess || registerPhase !== "registering") return;
    setRegisterPhase("idle");
    closePairing();
    onDeviceRegistered();
  }, [isRegisterSuccess]);

  function closePairing() {
    setIsOpen(false);
    setAddressInput("");
    setLabelInput("");
    setRegisterPhase("idle");
    setSalt(null);
  }

  function handleRegister() {
    if (!isConnected) { openConnectModal(); return; }
    if (!controllerAddress || !isAddress(addressInput) || !labelInput) return;

    const saltBytes = crypto.getRandomValues(new Uint8Array(32));
    const newSalt = `0x${Array.from(saltBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}` as `0x${string}`;
    setSalt(newSalt);

    const commitment = keccak256(
      encodePacked(
        ["address", "bytes32", "address"],
        [addressInput as `0x${string}`, newSalt, controllerAddress]
      )
    );

    setRegisterPhase("committing");
    sendCommit({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "commitDevice",
      args: [commitment],
    });
  }

  if (!isOpen) {
    return (
      <button onClick={() => setIsOpen(true)}>+ Add device</button>
    );
  }

  const addressIsValid = addressInput.length === 0 || isAddress(addressInput);

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>Add device</h3>

      <p className="muted">
        On your phone, open <strong>Devices → Show QR to pair</strong> and
        paste the displayed address here:
      </p>

      <div className="field">
        <label>Device address</label>
        <input
          value={addressInput}
          onChange={(e) => setAddressInput(e.target.value.trim())}
          placeholder="0x..."
          disabled={registerPhase !== "idle"}
          style={{ fontFamily: "monospace" }}
        />
        {!addressIsValid && <p className="error-text">Invalid address.</p>}
      </div>

      <div className="field">
        <label>Device name</label>
        <input
          value={labelInput}
          onChange={(e) => setLabelInput(e.target.value)}
          placeholder="ex: iPhone 15 Pro"
          disabled={registerPhase !== "idle"}
        />
      </div>

      {isPairError && (
        <p className="error-text">
          {pairError?.message?.includes("rejected_by_user")
            ? "Transaction rejected on Ledger."
            : `Error: ${pairError?.message?.split("\n")[0]}`}
        </p>
      )}
      <div className="actions-row">
        <button
          onClick={handleRegister}
          disabled={!isAddress(addressInput) || !labelInput || registerPhase !== "idle"}
        >
          {registerPhase === "committing" && isRegisterPendingAny
            ? "Confirm in wallet (1/2)..."
            : registerPhase === "committing" && isRegisterConfirmingAny
            ? "Waiting for network (1/2)..."
            : registerPhase === "registering" && isRegisterPendingAny
            ? "Confirm in wallet (2/2)..."
            : registerPhase === "registering" && isRegisterConfirmingAny
            ? "Waiting for network (2/2)..."
            : "Register device"}
        </button>
        <button onClick={closePairing}>Cancel</button>
      </div>
    </div>
  );
}

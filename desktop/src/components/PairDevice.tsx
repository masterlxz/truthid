import { useEffect, useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { keccak256, encodePacked, encodeFunctionData, isAddress, type Hex } from "viem";
import { invoke } from "@tauri-apps/api/core";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI, TRUTHID_ACCOUNT_ABI } from "../config/contracts";
import { useWalletModal } from "../contexts/WalletModalContext";
import { useIdentity } from "../contexts/IdentityContext";
import { buildAccountCalls } from "../utils/buildAccountCalls";

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
//
// Desde a 14.8, `msg.sender` do DeviceRegistry precisa ser a smart account
// (é ela o `controller` da identidade, não o Ledger) — por isso as duas
// transações chamam `execute`/`executeBatch` na smart account em vez de
// chamar o DeviceRegistry diretamente. O Ledger continua sendo quem assina
// e paga o gás, só que agora por trás de um `execute`.

export function PairDevice({ onDeviceRegistered }: {
  onDeviceRegistered: () => void;
}) {
  const { isConnected } = useAccount();
  const { smartAccountAddress } = useIdentity();
  const { openConnectModal } = useWalletModal();

  const [isOpen, setIsOpen] = useState(false);
  const [addressInput, setAddressInput] = useState("");
  const [encryptionKey, setEncryptionKey] = useState("");
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
    reset: resetCommit,
  } = useWriteContract();

  const {
    writeContract: sendRegister,
    data: registerTxHash,
    isPending: isRegisterPending,
    isError: isRegisterError,
    error: registerError,
    reset: resetRegister,
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
    if (
      !isCommitSuccess ||
      registerPhase !== "committing" ||
      !salt ||
      !isAddress(addressInput) ||
      !smartAccountAddress
    )
      return;
    setRegisterPhase("registering");
    const timer = setTimeout(async () => {
      // Encrypt vault key for the new device (ECIES)
      let encryptedVaultKey: Hex = "0x";
      if (encryptionKey) {
        try {
          const b64 = await invoke<string>("encrypt_vault_key_for_device", {
            devicePubkeyHex: encryptionKey,
          });
          // Convert base64 blob to hex for the contract call
          const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
          encryptedVaultKey = `0x${Array.from(raw, (b) => b.toString(16).padStart(2, "0")).join("")}` as Hex;
        } catch {
          // Non-critical: pairing succeeds without vault key
        }
      }

      const { dest, value, func } = buildAccountCalls([
        {
          address: DEVICE_REGISTRY_ADDRESS,
          abi: DEVICE_REGISTRY_ABI,
          functionName: "registerDevice",
          args: [addressInput as `0x${string}`, labelInput, salt, encryptedVaultKey],
        },
        {
          address: smartAccountAddress,
          abi: TRUTHID_ACCOUNT_ABI,
          functionName: "addDevice",
          args: [addressInput as `0x${string}`],
        },
      ]);
      sendRegister({
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "executeBatch",
        args: [dest, value, func],
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

  // Sem isso, um commit ou reveal que reverte on-chain (ex: endereço já
  // registrado antes) deixava registerPhase preso em "committing"/"registering"
  // pra sempre — o botão "Register device" ficava desabilitado sem nenhuma
  // forma de tentar de novo, mesmo com o formulário ainda preenchido. Mesma
  // classe de bug já corrigida antes em CreateIdentity.tsx (débito #44).
  useEffect(() => {
    if (isCommitError || isRegisterError) setRegisterPhase("idle");
  }, [isCommitError, isRegisterError]);

  function closePairing() {
    setIsOpen(false);
    setAddressInput("");
    setEncryptionKey("");
    setLabelInput("");
    setRegisterPhase("idle");
    setSalt(null);
  }

  function handleRegister() {
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress || !isAddress(addressInput) || !labelInput) return;

    resetCommit();
    resetRegister();

    const saltBytes = crypto.getRandomValues(new Uint8Array(32));
    const newSalt = `0x${Array.from(saltBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}` as `0x${string}`;
    setSalt(newSalt);

    // O commitment precisa usar o endereço que vai de fato aparecer como
    // `msg.sender` no DeviceRegistry — a smart account, não o Ledger.
    const commitment = keccak256(
      encodePacked(
        ["address", "bytes32", "address"],
        [addressInput as `0x${string}`, newSalt, smartAccountAddress]
      )
    );

    setRegisterPhase("committing");
    sendCommit({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "execute",
      args: [
        DEVICE_REGISTRY_ADDRESS,
        0n,
        encodeFunctionData({
          abi: DEVICE_REGISTRY_ABI,
          functionName: "commitDevice",
          args: [commitment],
        }),
      ],
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
          paste the displayed data here:
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
          <label>Encryption key (optional)</label>
          <input
            value={encryptionKey}
            onChange={(e) => setEncryptionKey(e.target.value.trim())}
            placeholder="0x03... or 0x04..."
            disabled={registerPhase !== "idle"}
            style={{ fontFamily: "monospace", fontSize: "0.8rem" }}
          />
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

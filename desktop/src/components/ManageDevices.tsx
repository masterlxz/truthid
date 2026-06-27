import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { keccak256, encodePacked, isAddress } from "viem";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
} from "../config/contracts";
import { DesktopDevice } from "./DesktopDevice";

// ─── Componente principal ─────────────────────────────────────────────────────

export function ManageDevices({ username }: { username: string }) {
  // ── Leitura 1: buscar o identityId a partir do username ──────────────────
  // Por que precisamos do identityId? O contrato DeviceRegistry organiza os
  // devices por ID numérico, não por username. Então precisamos converter:
  //   username (string) → identityId (número)
  const { data: identity } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getIdentity",
    args: [username],
  });

  const identityId = identity?.id;

  // ── Leitura 2: buscar lista de pubkeys dos devices desta identidade ───────
  // getDevicesByIdentity retorna address[] — um array de endereços Ethereum,
  // um por device (incluindo os revogados).
  // `enabled: !!identityId` significa "só execute quando identityId existir".
  // O !! converte qualquer valor para boolean (undefined → false, 1n → true).
  const { data: devicePubKeys, refetch: refetchDevices } = useReadContract({
    address: DEVICE_REGISTRY_ADDRESS,
    abi: DEVICE_REGISTRY_ABI,
    functionName: "getDevicesByIdentity",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  // ── Leitura 3: buscar detalhes de cada device ─────────────────────────────
  // useReadContracts (plural) recebe um array de chamadas e as executa em
  // paralelo. É como chamar useReadContract várias vezes de uma só vez.
  // Cada item em `results` é { data, status } — o mesmo shape de useReadContract.
  const { data: deviceResults, refetch: refetchDeviceDetails } = useReadContracts({
    contracts: (devicePubKeys ?? []).map((pk) => ({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice" as const,
      args: [pk] as const,
    })),
    query: { enabled: !!devicePubKeys && devicePubKeys.length > 0 },
  });

  // Extraímos os dados de cada device (ignorando os que falharam na leitura).
  // useReadContracts retorna { result, status } por item — diferente do singular
  // que retorna { data }. Cada item pode ter falhado independentemente.
  const devices = (deviceResults ?? [])
    .map((r) => r.result)
    .filter(Boolean);

  // ── Revogar device ────────────────────────────────────────────────────────
  // Mesmo padrão do createIdentity: writeContract → aguardar hash → receipt
  const [revokingPubKey, setRevokingPubKey] = useState<string | null>(null);

  const {
    writeContract: sendRevoke,
    data: revokeTxHash,
    isPending: isRevokePending,
  } = useWriteContract();

  const { isLoading: isRevokeConfirming, isSuccess: isRevokeSuccess } =
    useWaitForTransactionReceipt({ hash: revokeTxHash });

  function handleRevoke(pubKey: string) {
    setRevokingPubKey(pubKey);
    sendRevoke({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "revokeDevice",
      args: [pubKey as `0x${string}`],
    });
  }

  // Quando a revogação confirmar, atualiza a lista
  useEffect(() => {
    if (isRevokeSuccess) {
      setRevokingPubKey(null);
      refetchDevices();
      refetchDeviceDetails();
    }
  }, [isRevokeSuccess]);

  return (
    <div>
      <h2>@{username}</h2>

      <DeviceList
        devices={devices as DeviceInfo[]}
        revokingPubKey={revokingPubKey}
        isRevokePending={isRevokePending}
        isRevokeConfirming={isRevokeConfirming}
        onRevoke={handleRevoke}
      />

      <hr />

      <PairDevice
        onDeviceRegistered={() => {
          refetchDevices();
          refetchDeviceDetails();
        }}
      />

      <hr />

      <DesktopDevice
        onRegistered={() => {
          refetchDevices();
          refetchDeviceDetails();
        }}
      />
    </div>
  );
}

// ─── Lista de devices ─────────────────────────────────────────────────────────

type DeviceInfo = {
  identityId: bigint;
  pubKey: string;
  label: string;
  addedAt: bigint;
  revoked: boolean;
  exists: boolean;
};

function DeviceList({
  devices,
  revokingPubKey,
  isRevokePending,
  isRevokeConfirming,
  onRevoke,
}: {
  devices: DeviceInfo[];
  revokingPubKey: string | null;
  isRevokePending: boolean;
  isRevokeConfirming: boolean;
  onRevoke: (pubKey: string) => void;
}) {
  if (devices.length === 0) {
    return <p>Nenhum device registrado ainda.</p>;
  }

  return (
    <div>
      <h3>Dispositivos</h3>
      {devices.map((device) => {
        const isBeingRevoked = revokingPubKey === device.pubKey;
        // addedAt vem em segundos (Unix timestamp do bloco)
        const addedDate = new Date(Number(device.addedAt) * 1000).toLocaleDateString("pt-BR");

        return (
          <div key={device.pubKey} style={{ marginBottom: "1rem" }}>
            <strong>{device.label}</strong>
            <span> — {device.revoked ? "❌ Revogado" : "✅ Ativo"}</span>
            <br />
            <small style={{ fontFamily: "monospace" }}>
              {device.pubKey.slice(0, 10)}…{device.pubKey.slice(-6)}
            </small>
            <small> · Adicionado em {addedDate}</small>
            <br />
            {!device.revoked && (
              <button
                onClick={() => onRevoke(device.pubKey)}
                disabled={isRevokePending || isRevokeConfirming}
              >
                {isBeingRevoked && isRevokePending
                  ? "Confirme no MetaMask..."
                  : isBeingRevoked && isRevokeConfirming
                  ? "Aguardando rede..."
                  : "Revogar"}
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ─── Pareamento ──────────────────────────────────────────────────────────────

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

function PairDevice({ onDeviceRegistered }: {
  onDeviceRegistered: () => void;
}) {
  const { address: controllerAddress } = useAccount();

  const [isOpen, setIsOpen] = useState(false);
  const [addressInput, setAddressInput] = useState("");
  const [labelInput, setLabelInput] = useState("");

  // Registro em 2 passos (commit-reveal) — esconde o devicePubKey até a
  // confirmação, impedindo front-running (ver auditoria, achado #7).
  const [registerPhase, setRegisterPhase] = useState<"idle" | "committing" | "registering">("idle");
  const [salt, setSalt] = useState<`0x${string}` | null>(null);

  const {
    writeContract: sendRegister,
    data: registerTxHash,
    isPending: isRegisterPending,
  } = useWriteContract();

  const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess } =
    useWaitForTransactionReceipt({ hash: registerTxHash });

  useEffect(() => {
    if (!isRegisterSuccess) return;

    if (registerPhase === "committing" && salt && isAddress(addressInput)) {
      // Commit confirmado — passo 2: revelar devicePubKey + salt
      setRegisterPhase("registering");
      sendRegister({
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "registerDevice",
        args: [addressInput as `0x${string}`, labelInput, salt],
      });
    } else if (registerPhase === "registering") {
      setRegisterPhase("idle");
      closePairing();
      onDeviceRegistered();
    }
  }, [isRegisterSuccess]);

  function closePairing() {
    setIsOpen(false);
    setAddressInput("");
    setLabelInput("");
    setRegisterPhase("idle");
    setSalt(null);
  }

  function handleRegister() {
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
    sendRegister({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "commitDevice",
      args: [commitment],
    });
  }

  if (!isOpen) {
    return (
      <button onClick={() => setIsOpen(true)}>+ Adicionar dispositivo</button>
    );
  }

  const addressIsValid = addressInput.length === 0 || isAddress(addressInput);

  return (
    <div>
      <h3>Adicionar dispositivo</h3>

      <p>
        No celular, abra <strong>Dispositivos → Mostrar QR para parear</strong> e
        cole aqui o endereço exibido:
      </p>

      <label>
        Endereço do dispositivo:
        <br />
        <input
          value={addressInput}
          onChange={(e) => setAddressInput(e.target.value.trim())}
          placeholder="0x..."
          disabled={registerPhase !== "idle"}
          style={{ fontFamily: "monospace", width: "100%" }}
        />
      </label>
      {!addressIsValid && <p style={{ color: "red" }}>Endereço inválido.</p>}

      <br />
      <label>
        Nome do dispositivo:
        <br />
        <input
          value={labelInput}
          onChange={(e) => setLabelInput(e.target.value)}
          placeholder="ex: iPhone 15 Pro"
          disabled={registerPhase !== "idle"}
        />
      </label>
      <br />
      <button
        onClick={handleRegister}
        disabled={!isAddress(addressInput) || !labelInput || registerPhase !== "idle"}
      >
        {registerPhase === "committing" && isRegisterPending
          ? "Confirme no MetaMask (1/2)..."
          : registerPhase === "committing" && isRegisterConfirming
          ? "Preparando registro (1/2)..."
          : registerPhase === "registering" && isRegisterPending
          ? "Confirme no MetaMask (2/2)..."
          : registerPhase === "registering" && isRegisterConfirming
          ? "Aguardando rede (2/2)..."
          : "Registrar dispositivo"}
      </button>

      <br />
      <button onClick={closePairing}>Cancelar</button>
    </div>
  );
}

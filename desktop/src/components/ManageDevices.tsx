import { useEffect, useRef, useState } from "react";
import {
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { QRCodeSVG } from "qrcode.react";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
} from "../config/contracts";

// URL do servidor de sinalização (o mesmo da Fase 2)
const SIGNALING_URL = "http://localhost:8000";

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
        signalingUrl={SIGNALING_URL}
        onDeviceRegistered={() => {
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

// ─── Pareamento via QR ────────────────────────────────────────────────────────

// Este componente:
// 1. Cria uma sala no servidor de sinalização (POST /rooms)
// 2. Gera um QR code com as informações de conexão
// 3. Abre um WebSocket na sala e aguarda o mobile se conectar
// 4. Quando o mobile envia sua chave pública, registra o device na blockchain

function PairDevice({ signalingUrl, onDeviceRegistered }: {
  signalingUrl: string;
  onDeviceRegistered: () => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [pairRequest, setPairRequest] = useState<{ pubKey: string; label: string } | null>(null);
  const [labelInput, setLabelInput] = useState("");
  const [error, setError] = useState<string | null>(null);

  // useRef: guarda a conexão WebSocket sem causar re-render quando muda.
  // É como uma variável de instância — existe na "memória" do componente,
  // mas alterá-la não redesenha a tela.
  const wsRef = useRef<WebSocket | null>(null);

  const {
    writeContract: sendRegister,
    data: registerTxHash,
    isPending: isRegisterPending,
  } = useWriteContract();

  const { isLoading: isRegisterConfirming, isSuccess: isRegisterSuccess } =
    useWaitForTransactionReceipt({ hash: registerTxHash });

  // Quando o registro confirmar, avisa o pai e fecha o painel
  useEffect(() => {
    if (isRegisterSuccess) {
      closePairing();
      onDeviceRegistered();
    }
  }, [isRegisterSuccess]);

  // ── Abrir o painel de pareamento ──────────────────────────────────────────
  async function startPairing() {
    setError(null);
    setPairRequest(null);
    setLabelInput("");

    // 1. Criar sala no servidor de sinalização
    let id: string;
    try {
      const res = await fetch(`${signalingUrl}/rooms`, { method: "POST" });
      const json = await res.json();
      id = json.room_id;
    } catch {
      setError("Servidor de sinalização indisponível. Rode o signaling server primeiro.");
      return;
    }

    setRoomId(id);
    setIsOpen(true);

    // 2. Abrir WebSocket na sala e esperar o mobile se conectar
    // `new WebSocket(url)` abre uma conexão persistente com o servidor.
    // Diferente de fetch (que faz uma requisição e fecha), WebSocket fica
    // aberto e recebe mensagens a qualquer momento.
    const ws = new WebSocket(`ws://localhost:8000/rooms/${id}`);

    ws.onmessage = (event) => {
      // O mobile vai enviar: { type: "pair-request", pubKey: "0x...", label: "iPhone 15" }
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === "pair-request" && msg.pubKey && msg.label) {
          setPairRequest({ pubKey: msg.pubKey, label: msg.label });
          setLabelInput(msg.label);
        }
      } catch {
        // ignora mensagens malformadas
      }
    };

    ws.onerror = () => setError("Erro na conexão WebSocket com o servidor de sinalização.");

    wsRef.current = ws;
  }

  function closePairing() {
    wsRef.current?.close();
    wsRef.current = null;
    setIsOpen(false);
    setRoomId(null);
    setPairRequest(null);
    setLabelInput("");
    setError(null);
  }

  // Fechar WebSocket quando o componente for desmontado da tela
  // (useEffect com array vazio + return = "roda na desmontagem")
  useEffect(() => {
    return () => wsRef.current?.close();
  }, []);

  function handleRegister() {
    if (!pairRequest) return;
    sendRegister({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "registerDevice",
      args: [pairRequest.pubKey as `0x${string}`, labelInput],
    });
  }

  if (!isOpen) {
    return (
      <button onClick={startPairing}>+ Adicionar device via QR</button>
    );
  }

  // O QR code contém um JSON com:
  //   - action: identifica que é um pedido de pareamento TruthID
  //   - signalingUrl: onde o mobile deve se conectar
  //   - roomId: qual sala entrar
  const qrPayload = JSON.stringify({
    action: "truthid-pair",
    signalingUrl: "ws://localhost:8000",
    roomId,
  });

  return (
    <div>
      <h3>Adicionar dispositivo</h3>

      {error && <p style={{ color: "red" }}>{error}</p>}

      {!pairRequest && (
        <>
          <p>Escaneie o QR code com o app TruthID no seu celular:</p>
          <QRCodeSVG value={qrPayload} size={200} />
          <br />
          <small style={{ fontFamily: "monospace", wordBreak: "break-all" }}>
            Sala: {roomId}
          </small>
          <p><em>Aguardando o celular se conectar...</em></p>
        </>
      )}

      {pairRequest && (
        <div>
          <p>Dispositivo encontrado: <strong>{pairRequest.pubKey.slice(0, 10)}…</strong></p>
          <label>
            Nome do dispositivo:
            <br />
            <input
              value={labelInput}
              onChange={(e) => setLabelInput(e.target.value)}
              placeholder="ex: iPhone 15 Pro"
              disabled={isRegisterPending || isRegisterConfirming}
            />
          </label>
          <br />
          <button
            onClick={handleRegister}
            disabled={!labelInput || isRegisterPending || isRegisterConfirming}
          >
            {isRegisterPending
              ? "Confirme no MetaMask..."
              : isRegisterConfirming
              ? "Aguardando rede..."
              : "Registrar dispositivo"}
          </button>
        </div>
      )}

      <br />
      <button onClick={closePairing}>Cancelar</button>
    </div>
  );
}

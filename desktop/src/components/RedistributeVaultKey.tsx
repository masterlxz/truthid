import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { bytesToHex, type Address } from "viem";
import { DEVICE_REGISTRY_ADDRESS, DEVICE_REGISTRY_ABI, TRUTHID_ACCOUNT_ABI } from "../config/contracts";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import { useAccount } from "wagmi";
import { buildAccountCalls } from "../utils/buildAccountCalls";
import { base64ToBytes } from "../utils/base64";
import type { DeviceInfo } from "../types";

// Reenvia a vault key ATUAL (sem rotacionar nada, sem mudar o conteúdo
// publicado) pra um device já registrado — pro caso em que o pareamento
// original entregou uma chave errada e o device não consegue decifrar o
// vault, mesmo com o conteúdo certo (achado real, P54/Sessão 205).
// Diferente de `PairDevice.tsx`: não faz commit-reveal, só chama
// `updateDeviceVaultKey` direto (o device já existe on-chain) com uma
// cifra nova ECIES da chave que o Desktop usa hoje
// (`encrypt_vault_key_for_device`, agora sem o fallback legado silencioso —
// ver `get_current_vault_key_strict` no Rust).
//
// A chave pública crua (33/65 bytes) precisa ser reobtida do device (ex:
// tela "Show QR to pair" no mobile) — o contrato só guarda o endereço
// derivado dela, nunca a chave crua em si.
export function RedistributeVaultKey({ devices }: { devices: DeviceInfo[] }) {
  const { isConnected } = useAccount();
  const { smartAccountAddress } = useIdentity();
  const { openConnectModal } = useWalletModal();

  const [isOpen, setIsOpen] = useState(false);
  const [targetPubKey, setTargetPubKey] = useState<Address | "">("");
  const [rawPubkeyHex, setRawPubkeyHex] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isEncrypting, setIsEncrypting] = useState(false);

  const { writeContract: sendUpdate, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const activeDevices = devices.filter((d) => !d.revoked);

  async function handleSend() {
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress || !targetPubKey || !rawPubkeyHex) return;

    setError(null);
    setIsEncrypting(true);
    try {
      const blobB64 = await invoke<string>("encrypt_vault_key_for_device", {
        devicePubkeyHex: rawPubkeyHex,
      });
      const encryptedVaultKey = bytesToHex(base64ToBytes(blobB64));

      const { dest, value, func } = buildAccountCalls([
        {
          address: DEVICE_REGISTRY_ADDRESS,
          abi: DEVICE_REGISTRY_ABI,
          functionName: "updateDeviceVaultKey",
          args: [targetPubKey, encryptedVaultKey],
        },
      ]);
      reset();
      sendUpdate({
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "executeBatch",
        args: [dest, value, func],
      });
    } catch (e) {
      setError(String(e));
    } finally {
      setIsEncrypting(false);
    }
  }

  function close() {
    setIsOpen(false);
    setTargetPubKey("");
    setRawPubkeyHex("");
    setError(null);
  }

  if (!isOpen) {
    return (
      <button onClick={() => setIsOpen(true)} className="secondary">
        Redistribute vault key to a device
      </button>
    );
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>Redistribute vault key</h3>
      <p className="muted">
        Sends the vault key this Desktop uses today to an already-paired
        device — use this if that device can&apos;t decrypt the vault even
        though it has the right content (key mismatch, not a sync issue).
        You&apos;ll need its encryption key again (same field shown on the
        device&apos;s &quot;Show QR to pair&quot; screen).
      </p>

      <div className="field">
        <label>Device</label>
        <select
          value={targetPubKey}
          onChange={(e) => setTargetPubKey(e.target.value as Address)}
          disabled={isPending || isConfirming}
        >
          <option value="">Select a device...</option>
          {activeDevices.map((d) => (
            <option key={d.pubKey} value={d.pubKey}>
              {d.label} ({d.pubKey})
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label>Encryption key</label>
        <input
          value={rawPubkeyHex}
          onChange={(e) => setRawPubkeyHex(e.target.value.trim())}
          placeholder="0x03... or 0x04..."
          disabled={isPending || isConfirming}
          style={{ fontFamily: "monospace", fontSize: "0.8rem" }}
        />
      </div>

      {error && <p className="error-text">{error}</p>}
      {isSuccess && <p>Vault key sent — the device will pick it up next sync.</p>}

      <div className="actions-row">
        <button
          onClick={handleSend}
          disabled={!targetPubKey || !rawPubkeyHex || isEncrypting || isPending || isConfirming}
        >
          {isEncrypting
            ? "Encrypting..."
            : isPending
            ? "Confirm in wallet..."
            : isConfirming
            ? "Waiting for network..."
            : "Send current key"}
        </button>
        <button onClick={close}>Close</button>
      </div>
    </div>
  );
}

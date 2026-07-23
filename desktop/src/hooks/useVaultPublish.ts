import { useEffect, useState } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { encodeFunctionData } from "viem";
import { invoke } from "@tauri-apps/api/core";
import { useIdentity } from "../contexts/IdentityContext";
import { useWalletModal } from "../contexts/WalletModalContext";
import {
  VAULT_REGISTRY_ADDRESS,
  VAULT_REGISTRY_ABI,
  TRUTHID_ACCOUNT_ABI,
} from "../config/contracts";
import { publishVaultViaDeviceKey } from "../services/vaultPublishViaDeviceKey";
import type { PinResult } from "../types";

// Débito #43: máquina de estados de "publicar o vault" (vault_publish local +
// updateVault on-chain) extraída do VaultManagement.tsx, mesmo padrão já usado
// em useSmartAccountActivity.ts — orquestração de wagmi isolada da JSX.
export function useVaultPublish(
  pendingCount: number,
  onPublished: () => void
): {
  hasVault: boolean | undefined;
  vaultRef: unknown;
  publishError: string | null;
  pinWarning: string | null;
  txErrorMessage: string | null;
  buttonLabel: string;
  buttonDisabled: boolean;
  handleEnviar: () => Promise<void>;
  deviceKeyDisabled: boolean;
  deviceKeyPublishState: "idle" | "publishing" | "error";
  deviceKeyError: string | null;
  handleEnviarViaDeviceKey: () => Promise<void>;
} {
  const { identityId, smartAccountAddress } = useIdentity();
  const { isConnected } = useAccount();
  const { openConnectModal } = useWalletModal();

  const [publishState, setPublishState] = useState<"idle" | "publishing" | "error">("idle");
  const [publishError, setPublishError] = useState<string | null>(null);
  const [pinWarning, setPinWarning] = useState<string | null>(null);
  const [pendingUpdate, setPendingUpdate] = useState<{
    cid: string;
    contentHash: `0x${string}`;
  } | null>(null);
  const [justPublished, setJustPublished] = useState(false);

  // Segundo caminho de publicação, ao lado do já existente (Ledger via
  // writeContract acima): assina via device key, sem toque físico, usando o
  // motor novo `executeViaUserOp` (13.9-irmã — ver PROJECT_STATE.md, "Desktop
  // ganha assinatura via device key"). Prova real de que o pipeline
  // UserOp+bundler funciona no Desktop, reaproveitando a mesma ação
  // (updateVault) que o caminho Ledger já usa — não substitui o caminho
  // existente, soma.
  const [deviceKeyPublishState, setDeviceKeyPublishState] = useState<
    "idle" | "publishing" | "error"
  >("idle");
  const [deviceKeyError, setDeviceKeyError] = useState<string | null>(null);

  const {
    writeContract,
    data: txHash,
    isPending: isTxPending,
    isError: isTxError,
    error: txError,
    reset: resetTx,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isTxReceiptReady, data: txReceipt } =
    useWaitForTransactionReceipt({ hash: txHash });

  const { data: hasVault, refetch: refetchHasVault } = useReadContract({
    address: VAULT_REGISTRY_ADDRESS,
    abi: VAULT_REGISTRY_ABI,
    functionName: "hasVault",
    args: [identityId!],
    query: { enabled: !!identityId },
  });

  const { data: vaultRef, refetch: refetchVaultRef } = useReadContract({
    address: VAULT_REGISTRY_ADDRESS,
    abi: VAULT_REGISTRY_ABI,
    functionName: "getVault",
    args: [identityId!],
    query: { enabled: !!identityId && !!hasVault },
  });

  // Roteado via TruthIDAccount.execute() contra a smart account — VaultRegistry
  // só aceita chamadas de quem resolve como controller da identidade (débito #33).
  useEffect(() => {
    if (!pendingUpdate) return;
    if (!isConnected) { openConnectModal(); return; }
    if (!smartAccountAddress) return;
    writeContract({
      address: smartAccountAddress,
      abi: TRUTHID_ACCOUNT_ABI,
      functionName: "execute",
      args: [
        VAULT_REGISTRY_ADDRESS,
        0n,
        encodeFunctionData({
          abi: VAULT_REGISTRY_ABI,
          functionName: "updateVault",
          args: [pendingUpdate.cid, pendingUpdate.contentHash],
        }),
      ],
    });
    setPendingUpdate(null);
  }, [pendingUpdate, isConnected, smartAccountAddress]);

  useEffect(() => {
    if (!isTxReceiptReady) return;
    if (txReceipt?.status === "reverted") {
      setPublishError("Transaction reverted on-chain");
      setPublishState("error");
      resetTx();
      return;
    }
    markAsPublished();
    resetTx();
  }, [isTxReceiptReady]);

  async function handleEnviar() {
    setPublishError(null);
    setPinWarning(null);
    setPublishState("publishing");
    try {
      const result = await invoke<PinResult>("vault_publish");
      if (result.providers_failed.length > 0 && result.providers_ok.length === 0) {
        throw new Error(`Todos os providers falharam: ${result.providers_failed.join(", ")}`);
      }
      if (result.providers_failed.length > 0) {
        setPinWarning(
          `Redundância parcial: falhou em ${result.providers_failed.join(", ")} ` +
          `(ok em ${result.providers_ok.join(", ")}). O vault foi publicado, mas sem a redundância configurada.`
        );
      }
      setPendingUpdate({ cid: result.cid, contentHash: result.content_hash as `0x${string}` });
      setPublishState("idle");
    } catch (e) {
      setPublishError(String(e));
      setPublishState("error");
    }
  }

  async function handleEnviarViaDeviceKey() {
    setDeviceKeyError(null);
    setPinWarning(null);
    setDeviceKeyPublishState("publishing");
    try {
      if (!smartAccountAddress) {
        throw new Error("Nenhuma identidade carregada.");
      }

      const { transactionHash, providersFailed } = await publishVaultViaDeviceKey(smartAccountAddress);

      if (providersFailed.length > 0) {
        setPinWarning(
          `Redundância parcial: falhou em ${providersFailed.join(", ")} ` +
          `(ok no restante). O vault foi publicado, mas sem a redundância configurada.`
        );
      }

      if (!transactionHash) {
        throw new Error(
          "UserOperation enviada mas não confirmada a tempo — pode confirmar depois, não é necessariamente um erro."
        );
      }

      markAsPublished();
      setDeviceKeyPublishState("idle");
    } catch (e) {
      setDeviceKeyError(String(e));
      setDeviceKeyPublishState("error");
    }
  }

  function markAsPublished() {
    refetchHasVault();
    refetchVaultRef();
    onPublished();
    setJustPublished(true);
    setTimeout(() => setJustPublished(false), 3000);
  }

  function buttonLabel(): string {
    if (publishState === "publishing") return "Publicando no IPFS...";
    if (isTxPending) return "Confirmar na carteira...";
    if (isConfirming) return "Aguardando rede...";
    if (justPublished) return "Enviado ✓";
    if (pendingCount > 0) return `Enviar (${pendingCount} pendente${pendingCount > 1 ? "s" : ""})`;
    return "Enviar";
  }

  return {
    hasVault,
    vaultRef,
    publishError,
    pinWarning,
    txErrorMessage: isTxError && txError ? txError.message?.split("\n")[0] ?? null : null,
    buttonLabel: buttonLabel(),
    buttonDisabled: publishState === "publishing" || isTxPending || isConfirming || justPublished
      || deviceKeyPublishState === "publishing",
    handleEnviar,
    deviceKeyDisabled: deviceKeyPublishState === "publishing"
      || publishState === "publishing" || isTxPending || isConfirming || justPublished,
    deviceKeyPublishState,
    deviceKeyError,
    handleEnviarViaDeviceKey,
  };
}

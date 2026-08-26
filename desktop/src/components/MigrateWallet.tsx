import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { useQueryClient } from "@tanstack/react-query";
import {
  useAccount,
  useBalance,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { type Address, formatEther } from "viem";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  FACTORY_ADDRESS,
  FACTORY_ABI,
  TRUTHID_ACCOUNT_ABI,
} from "../config/contracts";
import { buildAccountCalls } from "../utils/buildAccountCalls";
import { useIdentity } from "../contexts/IdentityContext";
import { ConnectWallet } from "./ConnectWallet";

type Phase = "intro" | "connectNew" | "confirmNew" | "connectOld" | "review" | "confirming" | "done";

// Migra o `owner` de uma identidade pra outra wallet (P78 pedaço 2 —
// ex: wallet local↔hardware wallet, ou o inverso).
//
// `TruthIDAccount.owner` é `immutable` (contracts/src/TruthIDAccount.sol:88)
// — nunca pode ser trocado numa conta já implantada. "Migrar" é: implantar
// uma conta NOVA pro owner novo, trocar `IdentityRegistry.controller` pra
// ela e mover o saldo — tudo num único `executeBatch` assinado pelo owner
// ANTIGO (as duas primeiras chamadas + a transferência de saldo cabem na
// mesma transação porque `execute`/`executeBatch` só fazem `dest.call`).
// Reautorizar devices (`addDevice`) na conta nova precisa da assinatura do
// owner NOVO — uma chave diferente, então não cabe nessa mesma transação
// de jeito nenhum — mas isso já é coberto pelo banner "Reautorizar devices"
// que `ManageDevices.tsx` já mostra sozinho assim que detecta a lacuna
// (mesmo mecanismo do P53).
//
// Guardiões (RecoveryManager) e o histórico de devices (DeviceRegistry) são
// indexados por `identityId`, nunca pelo endereço da smart account —
// sobrevivem à migração sem nenhuma ação extra.
//
// O app só sustenta uma conexão wagmi ativa por vez (`storage: null` em
// `config/wagmi.ts`, reconectar é sempre manual) — por isso o fluxo é
// sequencial: conectar a wallet NOVA só pra aprender o endereço dela (sem
// gastar gas), desconectar, reconectar a wallet ANTIGA pra assinar a
// migração.
export function MigrateWallet({
  onClose,
  onBusyChange,
}: {
  onClose: () => void;
  onBusyChange?: (busy: boolean) => void;
}) {
  const { t } = useTranslation();
  const { username, smartAccountAddress } = useIdentity();
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const queryClient = useQueryClient();

  const [phase, setPhase] = useState<Phase>("intro");
  const [newOwnerAddress, setNewOwnerAddress] = useState<Address | null>(null);

  const { data: oldBalance, isLoading: isOldBalanceLoading } = useBalance({
    address: smartAccountAddress ?? undefined,
    query: { enabled: !!smartAccountAddress },
  });

  const { data: predictedNewAccount } = useReadContract({
    address: FACTORY_ADDRESS,
    abi: FACTORY_ABI,
    functionName: "getAddress",
    args: newOwnerAddress ? [newOwnerAddress, 0n] : undefined,
    query: { enabled: !!newOwnerAddress },
  });

  const isSameWallet = !!predictedNewAccount && predictedNewAccount === smartAccountAddress;

  // Captura o endereço da wallet nova assim que ela conecta, depois
  // desconecta sozinho — não precisa continuar conectado (a conta nova é
  // implantada de forma permissionless, pela wallet ANTIGA, na fase seguinte).
  const disconnectedForCapture = useRef(false);
  useEffect(() => {
    if (phase === "connectNew" && isConnected && address && !disconnectedForCapture.current) {
      disconnectedForCapture.current = true;
      setNewOwnerAddress(address);
      setPhase("confirmNew");
      disconnect();
    }
    if (phase !== "connectNew") disconnectedForCapture.current = false;
  }, [phase, isConnected, address, disconnect]);

  useEffect(() => {
    if (phase === "connectOld" && isConnected) setPhase("review");
  }, [phase, isConnected]);

  const {
    writeContract,
    data: txHash,
    isPending,
    isError,
    error,
    reset: resetTx,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // Mesmo guard de disparo duplicado de CreateIdentity.tsx/WithdrawModal.tsx —
  // `isPending` do React Query não atualiza no mesmo tick da chamada.
  const txSubmitted = useRef(false);

  useEffect(() => {
    if (
      phase === "confirming" &&
      !isOldBalanceLoading &&
      !txHash &&
      !isPending &&
      !isConfirming &&
      !txSubmitted.current &&
      newOwnerAddress &&
      predictedNewAccount &&
      smartAccountAddress
    ) {
      txSubmitted.current = true;
      const { dest, value, func } = buildAccountCalls([
        {
          address: FACTORY_ADDRESS,
          abi: FACTORY_ABI,
          functionName: "createAccount",
          args: [newOwnerAddress, 0n],
        },
        {
          address: IDENTITY_REGISTRY_ADDRESS,
          abi: IDENTITY_REGISTRY_ABI,
          functionName: "transferController",
          args: [username, predictedNewAccount],
        },
      ]);
      const balanceToMove = oldBalance?.value ?? 0n;
      if (balanceToMove > 0n) {
        dest.push(predictedNewAccount);
        value.push(balanceToMove);
        func.push("0x");
      }
      writeContract({
        address: smartAccountAddress,
        abi: TRUTHID_ACCOUNT_ABI,
        functionName: "executeBatch",
        args: [dest, value, func],
      });
    }
  }, [
    phase,
    isOldBalanceLoading,
    txHash,
    isPending,
    isConfirming,
    writeContract,
    newOwnerAddress,
    predictedNewAccount,
    smartAccountAddress,
    username,
    oldBalance,
  ]);

  useEffect(() => {
    if (isSuccess) {
      setPhase("done");
      queryClient.invalidateQueries();
    }
  }, [isSuccess, queryClient]);

  // Avisa o Settings/App.tsx que uma migração está em andamento (transação
  // já enviada) — pra eles guardarem o backdrop/✕ do modal de Configurações
  // e não derrubar isso no meio do caminho (achado real, P84 #4): esta tela
  // já não mostra nenhum botão de cancelar durante "confirming" por design,
  // mas o modal externo não sabia disso e fechava tudo incondicionalmente.
  useEffect(() => {
    onBusyChange?.(phase === "confirming");
    return () => onBusyChange?.(false);
  }, [phase, onBusyChange]);

  function handleRetry() {
    txSubmitted.current = false;
    resetTx();
  }

  function handleChooseDifferentWallet() {
    setNewOwnerAddress(null);
    setPhase("connectNew");
  }

  if (phase === "done") {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("migrateWallet.done.title")}</p>
        <code className="address">{predictedNewAccount}</code>
        <p className="muted" style={{ marginTop: "0.75rem", lineHeight: "1.5" }}>
          {t("migrateWallet.done.nextSteps")}
        </p>
        <p className="muted" style={{ marginTop: "0.5rem", fontSize: "0.85rem" }}>
          {t("migrateWallet.done.oldAddressWarning")}
        </p>
        <div className="actions-row">
          <button onClick={onClose}>{t("migrateWallet.close")}</button>
        </div>
      </div>
    );
  }

  if (phase === "intro") {
    return (
      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("migrateWallet.intro.title")}</h3>
        <p className="muted" style={{ lineHeight: "1.5" }}>{t("migrateWallet.intro.explanation")}</p>
        <p className="muted" style={{ lineHeight: "1.5" }}>{t("migrateWallet.intro.guardiansAndDevicesSurvive")}</p>
        <div className="actions-row">
          <button onClick={() => setPhase("connectNew")}>{t("migrateWallet.intro.start")}</button>
          <button type="button" onClick={onClose}>{t("migrateWallet.cancel")}</button>
        </div>
      </div>
    );
  }

  if (phase === "connectNew" || phase === "connectOld") {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.75rem", lineHeight: "1.5" }}>
          {phase === "connectNew"
            ? t("migrateWallet.connectNew.instruction")
            : t("migrateWallet.connectOld.instruction")}
        </p>
        <ConnectWallet asModal onClose={onClose} />
      </div>
    );
  }

  if (phase === "confirmNew") {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("migrateWallet.confirmNew.newOwnerLabel")}</p>
        <code className="address">{newOwnerAddress}</code>
        <p className="muted" style={{ marginTop: "0.75rem", marginBottom: "0.25rem" }}>
          {t("migrateWallet.confirmNew.newAccountLabel")}
        </p>
        <code className="address">{predictedNewAccount}</code>

        {isSameWallet && (
          <p className="error-text" style={{ marginTop: "0.75rem" }}>
            {t("migrateWallet.confirmNew.sameWalletError")}
          </p>
        )}

        <div className="actions-row">
          <button
            onClick={() => setPhase("connectOld")}
            disabled={!predictedNewAccount || isSameWallet}
          >
            {t("migrateWallet.confirmNew.confirmButton")}
          </button>
          <button type="button" onClick={handleChooseDifferentWallet}>
            {t("migrateWallet.confirmNew.chooseDifferentWallet")}
          </button>
        </div>
      </div>
    );
  }

  // phase === "review" || phase === "confirming"
  return (
    <div className="card">
      <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("migrateWallet.review.oldAccountLabel")}</p>
      <code className="address">{smartAccountAddress}</code>
      <p className="muted" style={{ marginTop: "0.25rem", fontSize: "0.85rem" }}>
        {t("migrateWallet.review.oldBalance", { amount: formatEther(oldBalance?.value ?? 0n) })}
      </p>

      <p className="muted" style={{ marginTop: "0.75rem", marginBottom: "0.25rem" }}>
        {t("migrateWallet.review.newAccountLabel")}
      </p>
      <code className="address">{predictedNewAccount}</code>

      {isError && (
        <p className="error-text" style={{ marginTop: "0.75rem" }}>
          {error?.message?.includes("rejected_by_user")
            ? t("migrateWallet.review.rejectedOnWallet")
            : t("migrateWallet.review.errorPrefix", { message: error?.message?.split("\n")[0] ?? "" })}
        </p>
      )}

      <div className="actions-row">
        {phase === "review" && (
          <button onClick={() => setPhase("confirming")}>{t("migrateWallet.review.confirmButton")}</button>
        )}
        {phase === "confirming" && (
          <button type="button" disabled>
            {isPending
              ? t("migrateWallet.review.confirmInWallet")
              : isConfirming
              ? t("migrateWallet.review.waitingForConfirmation")
              : t("migrateWallet.review.confirming")}
          </button>
        )}
        {isError && (
          <button type="button" onClick={handleRetry}>{t("migrateWallet.review.tryAgain")}</button>
        )}
        {phase === "review" && (
          <button type="button" onClick={onClose}>{t("migrateWallet.cancel")}</button>
        )}
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import {
  useAccount,
  useChainId,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useSendTransaction,
  useSignMessage,
} from "wagmi";
import { type Address, hexToSignature, parseEther } from "viem";
import {
  IDENTITY_REGISTRY_ADDRESS,
  IDENTITY_REGISTRY_ABI,
  FACTORY_ADDRESS,
  FACTORY_ABI,
} from "../config/contracts";
import { buildIdentityConsentHash } from "../utils/buildIdentityConsentHash";
import { VAULT_KEY_MESSAGE } from "../config/vaultKey";

const USERNAME_REGEX = /^[a-z0-9.\-]{1,64}$/;

const DEFAULT_FUNDING_ETH = "0.001";

export function CreateIdentity({ smartAccountAddress }: { smartAccountAddress: Address }) {
  const { t } = useTranslation();
  const [username, setUsername] = useState("");
  const [fundingEth, setFundingEth] = useState(DEFAULT_FUNDING_ETH);
  const [step, setStep] = useState<0 | 1 | 2 | 3 | 4>(0);
  const { address } = useAccount();
  const chainId = useChainId();

  const queryClient = useQueryClient();

  const { data: existingUsername } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: [smartAccountAddress],
  });

  const { data: isTaken } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "isUsernameTaken",
    args: [username],
    query: { enabled: username.length > 0 },
  });

  // Step 1 — sign consent (debt #17): proves the wallet that will own the
  // smart account authorizes this exact (username, controller) pairing,
  // before createIdentity is called. Works with any connector — Ledger,
  // WalletConnect, or injected.
  const {
    signMessage: signConsent,
    data: consentSignature,
    isPending: signPending,
    isError: signError,
    error: signErr,
  } = useSignMessage();

  const {
    writeContract: createIdentity,
    data: tx1Hash,
    isPending: tx1Pending,
    isError: tx1Error,
    error: tx1Err,
  } = useWriteContract();

  const {
    isLoading: tx1Confirming,
    isSuccess: tx1Success,
  } = useWaitForTransactionReceipt({ hash: tx1Hash });

  const {
    writeContract: deployAccount,
    data: tx2Hash,
    isPending: tx2Pending,
    isError: tx2Error,
    error: tx2Err,
    reset: resetTx2,
  } = useWriteContract();

  const {
    isLoading: tx2Confirming,
    isSuccess: tx2Success,
  } = useWaitForTransactionReceipt({ hash: tx2Hash });

  const {
    sendTransaction: fundAccount,
    data: tx3Hash,
    isPending: tx3Pending,
    isError: tx3Error,
    error: tx3Err,
    reset: resetTx3,
  } = useSendTransaction();

  const {
    isLoading: tx3Confirming,
    isSuccess: tx3Success,
  } = useWaitForTransactionReceipt({ hash: tx3Hash });

  // ── Vault key derivation ──────────────────────────────────────────────────
  const [vaultKeyDerived, setVaultKeyDerived] = useState(false);

  const {
    signMessage: signVaultKey,
    data: vaultKeySig,
    isPending: signVaultPending,
    isError: signVaultError,
    error: signVaultErr,
  } = useSignMessage();

  useEffect(() => {
    if (!vaultKeySig) return;
    try {
      const { r, s, v } = hexToSignature(vaultKeySig);
      if (v == null) return;
      invoke("derive_vault_key_from_wallet", { r, s, v: Number(v) })
        .then(() => setVaultKeyDerived(true))
        .catch(() => {});
    } catch {
      // ignore
    }
  }, [vaultKeySig]);

  useEffect(() => {
    // Check if vault key already exists (from a previous session)
    invoke<boolean>("vault_key_exists")
      .then(setVaultKeyDerived)
      .catch(() => {});
  }, []);

  const overallError = signErr ?? tx1Err ?? tx2Err ?? tx3Err;
  const hasError = signError || tx1Error || tx2Error || tx3Error;

  useEffect(() => {
    if (consentSignature) setStep(2);
  }, [consentSignature]);

  useEffect(() => {
    if (tx1Success) setStep(3);
  }, [tx1Success]);

  useEffect(() => {
    if (tx2Success) setStep(4);
  }, [tx2Success]);

  useEffect(() => {
    if (tx3Success || tx1Success) queryClient.invalidateQueries();
  }, [tx3Success, tx1Success, queryClient]);

  // Guards contra disparo duplicado: `writeContract`/`sendTransaction` (React
  // Query `mutate`) não atualiza `isPending` no mesmo tick da chamada — se o
  // efeito rodar de novo antes do próximo render, `!tx1Pending` ainda lê
  // `false` e a mutation dispara duas vezes (achado real: duas chamadas
  // `eth_sendTransaction` concorrentes brigando pelo mesmo HID da Ledger,
  // travando o dispositivo sem erro nenhum). O ref é síncrono, então cobre a
  // janela que o state assíncrono não cobre.
  const tx1Submitted = useRef(false);
  const tx2Submitted = useRef(false);
  const tx3Submitted = useRef(false);

  useEffect(() => {
    if (
      consentSignature &&
      step === 2 &&
      !tx1Hash &&
      !tx1Pending &&
      !tx1Confirming &&
      !tx1Submitted.current
    ) {
      tx1Submitted.current = true;
      const { r, s, v } = hexToSignature(consentSignature);
      if (v === undefined) throw new Error(t("createIdentity.errors.unexpectedConsentFormat"));
      createIdentity({
        address: IDENTITY_REGISTRY_ADDRESS,
        abi: IDENTITY_REGISTRY_ABI,
        functionName: "createIdentity",
        args: [username, smartAccountAddress, Number(v), r, s],
      });
    }
  }, [consentSignature, step, tx1Hash, tx1Pending, tx1Confirming, createIdentity, username, smartAccountAddress]);

  useEffect(() => {
    if (
      tx1Success &&
      step === 3 &&
      !tx2Hash &&
      !tx2Pending &&
      !tx2Confirming &&
      !tx2Submitted.current
    ) {
      tx2Submitted.current = true;
      deployAccount({
        address: FACTORY_ADDRESS,
        abi: FACTORY_ABI,
        functionName: "createAccount",
        args: [address!, 0n],
      });
    }
  }, [tx1Success, step, tx2Hash, tx2Pending, tx2Confirming, deployAccount, address]);

  useEffect(() => {
    if (
      tx2Success &&
      step === 4 &&
      !tx3Hash &&
      !tx3Pending &&
      !tx3Confirming &&
      !tx3Submitted.current
    ) {
      tx3Submitted.current = true;
      const value = (() => {
        try {
          return parseEther(fundingEth);
        } catch {
          return parseEther(DEFAULT_FUNDING_ETH);
        }
      })();
      // Explicit gas instead of relying on auto-estimation: `smartAccountAddress`
      // was deployed by tx2 just moments earlier, and estimating gas for a
      // transfer to it can race a public RPC node that hasn't caught up with
      // the new contract code yet — silently underestimating as a plain EOA
      // transfer (21000) instead of a call into `receive()` (~21220 measured).
      // The account's `receive()` is a trivial empty function, so a small
      // fixed margin above the measured cost is safe.
      fundAccount({ to: smartAccountAddress, value, gas: 30_000n });
    }
  }, [tx2Success, step, tx3Hash, tx3Pending, tx3Confirming, fundAccount, smartAccountAddress, fundingEth]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStep(1);
    const consentHash = buildIdentityConsentHash({
      chainId,
      identityRegistryAddress: IDENTITY_REGISTRY_ADDRESS,
      username,
      controller: smartAccountAddress,
    });
    signConsent({ message: { raw: consentHash } });
  }

  function handleRetry() {
    if (step === 3 && tx2Error) {
      tx2Submitted.current = false;
      resetTx2();
    } else if (step === 4 && tx3Error) {
      tx3Submitted.current = false;
      resetTx3();
    }
  }

  const isValidFormat = USERNAME_REGEX.test(username);
  const isFundingValid = (() => {
    try {
      return parseEther(fundingEth) > 0n;
    } catch {
      return false;
    }
  })();

  const isFormPending =
    signPending || tx1Pending || tx1Confirming || tx2Pending || tx2Confirming || tx3Pending || tx3Confirming;
  const canSubmit = step === 0 && isValidFormat && !isTaken && !isFormPending && isFundingValid;

  if (existingUsername) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("createIdentity.identityAlreadyRegistered")}</p>
        <strong>@{existingUsername as string}</strong>
      </div>
    );
  }

  if (tx3Success) {
    return (
      <div className="card">
        <p className="muted" style={{ marginBottom: "0.25rem" }}>{t("createIdentity.identityCreatedSuccess")}</p>
        <strong>@{username}</strong>
        <p className="muted" style={{ marginTop: "0.5rem" }}>
          {t("createIdentity.fundedWith", { amount: fundingEth })}
        </p>

        {!vaultKeyDerived && (
          <div style={{ marginTop: "1.5rem", paddingTop: "1rem", borderTop: "1px solid var(--color-border)" }}>
            <p className="muted" style={{ marginBottom: "0.75rem", lineHeight: "1.5" }}>
              {t("createIdentity.vaultKey.intro")}
            </p>
            {signVaultError && (
              <p className="error-text">
                {signVaultErr?.message?.includes("rejected_by_user")
                  ? t("createIdentity.vaultKey.signatureRejected")
                  : t("createIdentity.errors.prefixed", { message: signVaultErr?.message?.split("\n")[0] })}
              </p>
            )}
            <button
              onClick={() => signVaultKey({ message: VAULT_KEY_MESSAGE })}
              disabled={signVaultPending}
            >
              {signVaultPending ? t("createIdentity.vaultKey.confirmSignature") : t("createIdentity.vaultKey.setupButton")}
            </button>
          </div>
        )}

        {vaultKeyDerived && (
          <p className="muted" style={{ marginTop: "0.75rem" }}>
            {t("createIdentity.vaultKey.ready")}
          </p>
        )}
      </div>
    );
  }

  const steps = [
    { num: 1, label: t("createIdentity.steps.signingConsent"), active: step >= 1, done: step > 1 || !!consentSignature },
    { num: 2, label: t("createIdentity.steps.creatingIdentity"), active: step >= 2, done: step > 2 || tx1Success },
    { num: 3, label: t("createIdentity.steps.deployingAccount"), active: step >= 3, done: step > 3 || tx2Success },
    { num: 4, label: t("createIdentity.steps.fundingAccount"), active: step >= 4, done: tx3Success },
  ];

  return (
    <form onSubmit={handleSubmit} className="card">
      <h2>{t("createIdentity.form.title")}</h2>

      <div className="field">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value.toLowerCase())}
          placeholder={t("createIdentity.form.usernamePlaceholder")}
          disabled={isFormPending}
        />
      </div>

      {username.length > 0 && !isValidFormat && (
        <p className="muted">{t("createIdentity.form.usernameFormatHint")}</p>
      )}

      {isValidFormat && isTaken && (
        <p className="muted">{t("createIdentity.form.usernameTaken")}</p>
      )}

      <div className="field" style={{ marginTop: "0.75rem" }}>
        <label className="muted" style={{ display: "block", marginBottom: "0.25rem", fontSize: "0.85rem" }}>
          {t("createIdentity.form.fundingLabel")}
        </label>
        <input
          value={fundingEth}
          onChange={(e) => setFundingEth(e.target.value)}
          placeholder={DEFAULT_FUNDING_ETH}
          disabled={isFormPending}
          style={{ width: "8rem" }}
        />
      </div>

      {!isFundingValid && fundingEth.length > 0 && (
        <p className="muted">{t("createIdentity.form.fundingInvalid")}</p>
      )}

      <div className="muted" style={{ marginTop: "0.75rem", fontSize: "0.85rem", lineHeight: "1.5" }}>
        {t("createIdentity.form.explanation")}
      </div>

      {step > 0 && (
        <div style={{ marginTop: "1rem" }}>
          {steps.map((s) => (
            <div
              key={s.num}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "0.5rem",
                padding: "0.25rem 0",
                opacity: s.active ? 1 : 0.4,
              }}
            >
              <span>{s.done ? "✓" : s.active ? "●" : "○"}</span>
              <span>{s.label}</span>
            </div>
          ))}
        </div>
      )}

      {hasError && (
        <p className="error-text" style={{ marginTop: "0.5rem" }}>
          {overallError?.message?.includes("rejected_by_user")
            ? t("createIdentity.errors.rejectedOnLedger")
            : t("createIdentity.errors.prefixed", {
                message: overallError?.message?.split("\n")[0] ?? t("createIdentity.errors.operationFailed"),
              })}
        </p>
      )}

      {(step === 3 && tx2Error) || (step === 4 && tx3Error) ? (
        <button type="button" onClick={handleRetry} style={{ marginTop: "0.5rem" }}>
          {t("createIdentity.actions.tryAgain")}
        </button>
      ) : null}

      {step === 0 && (
        <button type="submit" disabled={!canSubmit}>
          {t("createIdentity.actions.registerIdentity")}
        </button>
      )}

      {step === 1 && (
        <button type="button" disabled>
          {signPending ? t("createIdentity.vaultKey.confirmSignature") : t("createIdentity.actions.step1of4")}
        </button>
      )}

      {step === 2 && (
        <button type="button" disabled>
          {tx1Pending
            ? t("createIdentity.actions.confirmTx2InWallet")
            : tx1Confirming
            ? t("createIdentity.actions.waitingForConfirmation")
            : t("createIdentity.actions.step2of4")}
        </button>
      )}

      {step === 3 && (
        <button type="button" disabled>
          {tx2Pending
            ? t("createIdentity.actions.confirmTx3InWallet")
            : tx2Confirming
            ? t("createIdentity.actions.waitingForConfirmation")
            : t("createIdentity.actions.step3of4")}
        </button>
      )}

      {step === 4 && (
        <button type="button" disabled>
          {tx3Pending
            ? t("createIdentity.actions.confirmTx4InWallet")
            : tx3Confirming
            ? t("createIdentity.actions.waitingForConfirmation")
            : t("createIdentity.actions.step4of4")}
        </button>
      )}
    </form>
  );
}

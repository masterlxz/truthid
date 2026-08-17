import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";

export function VaultSettings() {
  return (
    <div>
      <ArweaveWalletSection />
    </div>
  );
}

/**
 * Wallet Arweave (Etapa 2 da migração de storage, ver project/ROADMAP.md) —
 * o vault (blob principal + documentos anexados) e o canal `/truthid/v1/pin`
 * de apps terceiros publicam no Arweave em vez do IPFS, e isso exige uma
 * wallet local financiada com AR. Sem UI nenhuma pra isso, "Enviar" (ou uma
 * requisição de `/pin`) simplesmente falhava com o erro do Rust (`nenhuma
 * wallet Arweave configurada...`) sem nenhum jeito de resolver de dentro do
 * app.
 */
function ArweaveWalletSection() {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);
  const [exists, setExists] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [balanceWinston, setBalanceWinston] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  function loadWallet() {
    setLoading(true);
    invoke<boolean>("arweave_wallet_exists")
      .then(async (walletExists) => {
        setExists(walletExists);
        if (!walletExists) return;
        const addr = await invoke<string>("arweave_wallet_address");
        setAddress(addr);
        // Saldo é best-effort — uma wallet nova sem tráfego ainda deve
        // aparecer com endereço mesmo se a consulta de saldo falhar.
        try {
          setBalanceWinston(await invoke<string>("arweave_wallet_balance"));
        } catch {
          setBalanceWinston(null);
        }
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }

  useEffect(loadWallet, []);

  async function handleGenerate() {
    setError(null);
    setGenerating(true);
    try {
      const addr = await invoke<string>("arweave_generate_wallet");
      setAddress(addr);
      setExists(true);
      try {
        setBalanceWinston(await invoke<string>("arweave_wallet_balance"));
      } catch {
        setBalanceWinston(null);
      }
    } catch (e) {
      setError(String(e));
    } finally {
      setGenerating(false);
    }
  }

  async function handleCopy() {
    if (!address) return;
    await navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  if (loading) return null;

  // 1 AR = 10^12 winston.
  const balanceAr =
    balanceWinston !== null ? (Number(balanceWinston) / 1e12).toFixed(6) : null;

  return (
    <div className="card" style={{ marginBottom: "1.5rem" }}>
      <h2 style={{ marginTop: 0 }}>{t("vaultSettings.arweaveWallet.title")}</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        {t("vaultSettings.arweaveWallet.description")}
      </p>

      {error && <p className="error-text">{error}</p>}

      {!exists ? (
        <div className="actions-row">
          <button onClick={handleGenerate} disabled={generating}>
            {generating
              ? t("vaultSettings.arweaveWallet.generating")
              : t("vaultSettings.arweaveWallet.generate")}
          </button>
        </div>
      ) : (
        <div>
          <code className="donate-address" style={{ textAlign: "left", display: "block" }}>
            {address}
          </code>
          <div className="actions-row" style={{ marginTop: "0.5rem", alignItems: "center" }}>
            <button onClick={handleCopy} style={{ padding: "0.3em 0.75em", fontSize: "0.85em" }}>
              {copied
                ? t("vaultSettings.arweaveWallet.copied")
                : t("vaultSettings.arweaveWallet.copyAddress")}
            </button>
            <span className="muted" style={{ fontSize: "0.85em" }}>
              {balanceAr !== null
                ? t("vaultSettings.arweaveWallet.balance", { balance: balanceAr })
                : t("vaultSettings.arweaveWallet.balanceUnavailable")}
            </span>
          </div>
          {balanceAr !== null && Number(balanceAr) === 0 && (
            <p className="muted" style={{ fontSize: "0.85em", marginTop: "0.75rem", marginBottom: 0 }}>
              {t("vaultSettings.arweaveWallet.noBalanceWarning")}
            </p>
          )}
        </div>
      )}
    </div>
  );
}

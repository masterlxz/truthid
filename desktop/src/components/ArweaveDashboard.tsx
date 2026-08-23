import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { formatDateTime } from "../i18n/formatDate";

type ArweaveTxSummary = {
  id: string;
  block_height: number | null;
  block_timestamp: number | null;
  fee_ar: string;
  quantity_ar: string;
  recipient: string | null;
  app_name: string | null;
  content_type: string | null;
};

const HISTORY_PAGE_SIZE = 25;

/**
 * Visão Arweave do dashboard único (P67, toggle ETH↔Arweave) — funde a
 * gestão de wallet que morava em `VaultSettings.tsx`/`ArweaveWalletSection`
 * (gerar wallet, ver endereço+saldo) com um histórico de transações novo
 * (não existia em lugar nenhum antes desta sessão), via
 * `arweave_wallet_transactions` (GraphQL do gateway, `arweave/mod.rs`).
 */
export function ArweaveDashboard() {
  const { t, i18n } = useTranslation();

  const [loading, setLoading] = useState(true);
  const [exists, setExists] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [balanceWinston, setBalanceWinston] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const [history, setHistory] = useState<ArweaveTxSummary[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);

  const loadHistory = useCallback((addr: string) => {
    setHistoryLoading(true);
    setHistoryError(null);
    invoke<ArweaveTxSummary[]>("arweave_wallet_transactions", { address: addr, first: HISTORY_PAGE_SIZE })
      .then(setHistory)
      .catch((e) => setHistoryError(String(e)))
      .finally(() => setHistoryLoading(false));
  }, []);

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
        loadHistory(addr);
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
      loadHistory(addr);
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
    <div>
      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h2 style={{ marginTop: 0 }}>{t("arweaveDashboard.arweaveWallet.title")}</h2>
        <p className="muted" style={{ marginBottom: "1.25rem" }}>
          {t("arweaveDashboard.arweaveWallet.description")}
        </p>

        {error && <p className="error-text">{error}</p>}

        {!exists ? (
          <div className="actions-row">
            <button onClick={handleGenerate} disabled={generating}>
              {generating
                ? t("arweaveDashboard.arweaveWallet.generating")
                : t("arweaveDashboard.arweaveWallet.generate")}
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
                  ? t("arweaveDashboard.arweaveWallet.copied")
                  : t("arweaveDashboard.arweaveWallet.copyAddress")}
              </button>
              <span className="muted" style={{ fontSize: "0.85em" }}>
                {balanceAr !== null
                  ? t("arweaveDashboard.arweaveWallet.balance", { balance: balanceAr })
                  : t("arweaveDashboard.arweaveWallet.balanceUnavailable")}
              </span>
            </div>
            {balanceAr !== null && Number(balanceAr) === 0 && (
              <p className="muted" style={{ fontSize: "0.85em", marginTop: "0.75rem", marginBottom: 0 }}>
                {t("arweaveDashboard.arweaveWallet.noBalanceWarning")}
              </p>
            )}
          </div>
        )}
      </div>

      {exists && address && (
        <div className="card">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <h3 style={{ marginTop: 0 }}>{t("arweaveDashboard.history.title")}</h3>
            <button
              className="topbar-btn"
              style={{ fontSize: "0.8rem" }}
              onClick={() => loadHistory(address)}
            >
              {t("arweaveDashboard.history.refresh")}
            </button>
          </div>

          {historyLoading && <p className="muted">{t("arweaveDashboard.history.loading")}</p>}

          {historyError && !historyLoading && (
            <div>
              <p className="error-text">
                {t("arweaveDashboard.history.failedToLoad", { error: historyError.split("\n")[0] })}
              </p>
              <button onClick={() => loadHistory(address)}>{t("arweaveDashboard.history.retry")}</button>
            </div>
          )}

          {!historyLoading && !historyError && history.length === 0 && (
            <p className="muted">{t("arweaveDashboard.history.empty")}</p>
          )}

          {!historyLoading &&
            !historyError &&
            history.map((tx) => {
              const idShort = `${tx.id.slice(0, 10)}…${tx.id.slice(-6)}`;
              const isTransfer = tx.quantity_ar !== "0";
              return (
                <div key={tx.id} className="card">
                  <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", marginBottom: "0.4rem" }}>
                    <span className="status-badge status-badge--active">
                      {isTransfer
                        ? t("arweaveDashboard.history.quantity", { quantity: tx.quantity_ar })
                        : tx.content_type ?? t("arweaveDashboard.history.dataTx")}
                    </span>
                    <code className="address">{idShort}</code>
                  </div>
                  <span className="muted">
                    {tx.block_timestamp !== null
                      ? formatDateTime(tx.block_timestamp, i18n.language)
                      : t("arweaveDashboard.history.pending")}
                  </span>
                  <span className="muted"> · {t("arweaveDashboard.history.fee", { fee: tx.fee_ar })}</span>
                </div>
              );
            })}
        </div>
      )}
    </div>
  );
}

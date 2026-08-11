import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

interface PinAuthorization {
  appName: string;
  dailyLimit: number;
  usedToday: number;
  dayStartMs: number;
}

export function VaultSettings() {
  return (
    <div>
      <ArweaveWalletSection />
      <PinAuthorizationsSection />
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
      <h2 style={{ marginTop: 0 }}>Wallet Arweave</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        O vault (blob principal e documentos anexados) e os apps terceiros autorizados abaixo
        publicam no Arweave — precisa de uma wallet local financiada com AR.
      </p>

      {error && <p className="error-text">{error}</p>}

      {!exists ? (
        <div className="actions-row">
          <button onClick={handleGenerate} disabled={generating}>
            {generating ? "Gerando..." : "Gerar wallet Arweave"}
          </button>
        </div>
      ) : (
        <div>
          <code className="donate-address" style={{ textAlign: "left", display: "block" }}>
            {address}
          </code>
          <div className="actions-row" style={{ marginTop: "0.5rem", alignItems: "center" }}>
            <button onClick={handleCopy} style={{ padding: "0.3em 0.75em", fontSize: "0.85em" }}>
              {copied ? "✓ Copiado!" : "Copiar endereço"}
            </button>
            <span className="muted" style={{ fontSize: "0.85em" }}>
              {balanceAr !== null
                ? `Saldo: ${balanceAr} AR`
                : "Saldo indisponível no momento"}
            </span>
          </div>
          {balanceAr !== null && Number(balanceAr) === 0 && (
            <p className="muted" style={{ fontSize: "0.85em", marginTop: "0.75rem", marginBottom: 0 }}>
              Sem saldo ainda — compre AR numa exchange e envie pro endereço acima antes de
              clicar "Enviar".
            </p>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * Apps terceiros autorizados a usar a wallet Arweave acima via
 * /truthid/v1/pin (fatia 3 do débito registrado na Sessão 106). Separado
 * num componente próprio, com seu próprio load/save (`pin_get_authorizations`).
 */
function PinAuthorizationsSection() {
  const [authorizations, setAuthorizations] = useState<PinAuthorization[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Valor do input de limite por app, só enquanto difere do persistido —
  // evita que o campo "pule" pro valor salvo a cada re-render.
  const [limitDrafts, setLimitDrafts] = useState<Record<string, string>>({});

  function load() {
    setLoading(true);
    invoke<PinAuthorization[]>("pin_get_authorizations")
      .then(setAuthorizations)
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }

  useEffect(load, []);

  async function handleRevoke(appName: string) {
    setError(null);
    try {
      await invoke("pin_revoke_authorization", { appName });
      setAuthorizations((prev) => prev.filter((a) => a.appName !== appName));
    } catch (e) {
      setError(String(e));
    }
  }

  async function handleSaveLimit(appName: string) {
    const draft = limitDrafts[appName];
    const parsed = draft !== undefined ? Number.parseInt(draft, 10) : NaN;
    if (!Number.isFinite(parsed) || parsed <= 0) return;

    setError(null);
    try {
      await invoke("pin_set_daily_limit", { appName, dailyLimit: parsed });
      setAuthorizations((prev) =>
        prev.map((a) => (a.appName === appName ? { ...a, dailyLimit: parsed } : a))
      );
      setLimitDrafts((prev) => {
        const { [appName]: _removed, ...rest } = prev;
        return rest;
      });
    } catch (e) {
      setError(String(e));
    }
  }

  if (loading) return null;

  return (
    <div style={{ marginTop: "2rem" }}>
      <h2>Third-party app pinning access</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        Apps that requested to pin data using the Arweave wallet above via /pin. A new app
        always needs your approval first; once approved, it can pin up to its daily limit
        without asking again.
      </p>

      {error && <p className="error-text">{error}</p>}

      {authorizations.length === 0 ? (
        <p className="muted">No app has requested pinning access yet.</p>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
          {authorizations.map((a) => {
            const draft = limitDrafts[a.appName];
            const dirty = draft !== undefined && draft !== String(a.dailyLimit);
            return (
              <div
                key={a.appName}
                className="card"
                style={{ display: "flex", alignItems: "center", gap: "0.75rem", padding: "0.85rem 1.1rem" }}
              >
                <span style={{ fontWeight: 600, flex: 1 }}>{a.appName}</span>
                <span className="muted" style={{ fontSize: "0.85em", flexShrink: 0 }}>
                  {a.usedToday} / {a.dailyLimit} pins today
                </span>
                <input
                  type="number"
                  min={1}
                  value={draft ?? String(a.dailyLimit)}
                  onChange={(e) =>
                    setLimitDrafts((prev) => ({ ...prev, [a.appName]: e.target.value }))
                  }
                  style={{ width: "5rem", flexShrink: 0 }}
                />
                <button
                  onClick={() => handleSaveLimit(a.appName)}
                  disabled={!dirty}
                  style={{ padding: "0.3em 0.75em", fontSize: "0.85em", flexShrink: 0 }}
                >
                  Save
                </button>
                <button
                  onClick={() => handleRevoke(a.appName)}
                  style={{
                    padding: "0.3em 0.65em",
                    fontSize: "0.85em",
                    borderColor: "var(--color-danger)",
                    color: "var(--color-danger)",
                    flexShrink: 0,
                  }}
                >
                  Revoke
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

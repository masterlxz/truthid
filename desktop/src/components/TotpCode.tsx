import { useEffect, useState } from "react";
import { generateTotpCode, secondsRemaining } from "../utils/totp";

/** Mostra o código TOTP atual de uma entrada, com contagem regressiva e cópia
 * — mesmo padrão de "valor + botão copiar" de DepositModal.tsx/DonateModal.tsx. */
export function TotpCode({ secret }: { secret: string }) {
  const [code, setCode] = useState("······");
  const [remaining, setRemaining] = useState(30);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function tick() {
      const now = Math.floor(Date.now() / 1000);
      setRemaining(secondsRemaining(now));
      try {
        const c = await generateTotpCode(secret, now);
        if (!cancelled) {
          setCode(c);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(String(e));
      }
    }

    tick();
    const id = setInterval(tick, 1000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [secret]);

  async function handleCopy() {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  if (error) {
    return (
      <span className="error-text" style={{ fontSize: "0.8em" }}>
        2FA: {error}
      </span>
    );
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
      <code style={{ fontSize: "0.95em", letterSpacing: "0.05em" }}>
        {code.slice(0, 3)} {code.slice(3)}
      </code>
      <span className="muted" style={{ fontSize: "0.78em" }}>{remaining}s</span>
      <button onClick={handleCopy} style={{ padding: "0.15em 0.5em", fontSize: "0.78em" }}>
        {copied ? "✓" : "Copiar"}
      </button>
    </div>
  );
}

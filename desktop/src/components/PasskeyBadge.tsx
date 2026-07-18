import { useState } from "react";
import type { Passkey } from "../types";
import { signAssertion } from "../utils/webauthn";

function formatCreatedAt(secs: number) {
  return new Date(secs * 1000).toLocaleDateString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric",
  });
}

/** Mostra a credencial passkey de uma entrada (RP ID + data de criação) com um
 * botão "Testar assinatura" que roda uma cerimônia de asserção local, sem
 * nenhum site real envolvido — prova que o virtual authenticator funciona,
 * mesmo sem a interceptação de `navigator.credentials` (fora de escopo desta
 * fase). Mesmo padrão de "valor + ação" de TotpCode.tsx. */
export function PasskeyBadge({ passkey }: { passkey: Passkey }) {
  const [result, setResult] = useState<"idle" | "ok" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  function handleTest() {
    try {
      const challenge = crypto.getRandomValues(new Uint8Array(32));
      signAssertion({
        privateKeyHex: passkey.private_key_hex,
        rpId: passkey.rp_id,
        signCount: passkey.sign_count,
        challenge,
        origin: `https://${passkey.rp_id}`,
      });
      setResult("ok");
      setError(null);
    } catch (e) {
      setResult("error");
      setError(String(e));
    }
    setTimeout(() => setResult("idle"), 2000);
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
      <span className="status-badge" style={{ fontSize: "0.78em", padding: "0.15em 0.5em" }}>
        🔑 Passkey
      </span>
      <span className="muted" style={{ fontSize: "0.8em" }}>
        {passkey.rp_id} · {formatCreatedAt(passkey.created_at)}
      </span>
      <button onClick={handleTest} style={{ padding: "0.15em 0.5em", fontSize: "0.78em" }}>
        {result === "ok" ? "✓" : result === "error" ? "✕" : "Testar assinatura"}
      </button>
      {error && <span className="error-text" style={{ fontSize: "0.78em" }}>{error}</span>}
    </div>
  );
}

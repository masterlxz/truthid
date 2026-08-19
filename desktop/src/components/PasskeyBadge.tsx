import { useTranslation } from "react-i18next";
import type { Passkey } from "../types";
import { formatDate } from "../i18n/formatDate";

function formatCreatedAt(secs: number, language: string) {
  return formatDate(secs, language, { day: "2-digit", month: "2-digit", year: "numeric" });
}

/** Mostra a credencial passkey de uma entrada (RP ID + data de criação). */
export function PasskeyBadge({ passkey }: { passkey: Passkey }) {
  const { i18n } = useTranslation();

  return (
    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
      <span className="status-badge" style={{ fontSize: "0.78em", padding: "0.15em 0.5em" }}>
        🔑 Passkey
      </span>
      <span className="muted" style={{ fontSize: "0.8em" }}>
        {passkey.rp_id} · {formatCreatedAt(passkey.created_at, i18n.language)}
      </span>
    </div>
  );
}

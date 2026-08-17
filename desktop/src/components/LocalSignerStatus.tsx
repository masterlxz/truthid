import { useTranslation } from "react-i18next";
import { useLocalSignerServer } from "../hooks/useLocalSignerServer";

/**
 * Visibilidade + kill switch do canal local pra apps terceiros (fatia 2a).
 * Sem aprovação, sem decodificação de chamada — só liga/desliga o transporte.
 */
export function LocalSignerStatus() {
  const { t } = useTranslation();
  const { status, error, start, stop, isStopping } = useLocalSignerServer();

  if (!status) return null;

  return (
    <div className="card" style={{ marginTop: "0.75rem" }}>
      <h3 style={{ marginTop: 0 }}>{t("localSignerStatus.title")}</h3>
      {status.running ? (
        <span className="status-badge status-badge--active">
          {t("localSignerStatus.active", { port: status.port })}
        </span>
      ) : (
        <span className="status-badge status-badge--revoked">{t("localSignerStatus.inactive")}</span>
      )}
      {error && <p className="error-text">{error}</p>}
      <div className="actions-row" style={{ marginTop: "0.75rem" }}>
        {status.running ? (
          <button onClick={stop} disabled={isStopping}>
            {isStopping ? t("localSignerStatus.stopping") : t("localSignerStatus.stop")}
          </button>
        ) : (
          <button onClick={start}>{t("localSignerStatus.start")}</button>
        )}
      </div>
    </div>
  );
}

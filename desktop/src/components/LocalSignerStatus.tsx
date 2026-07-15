import { useLocalSignerServer } from "../hooks/useLocalSignerServer";

/**
 * Visibilidade + kill switch do canal local pra apps terceiros (fatia 2a).
 * Sem aprovação, sem decodificação de chamada — só liga/desliga o transporte.
 */
export function LocalSignerStatus() {
  const { status, error, start, stop } = useLocalSignerServer();

  if (!status) return null;

  return (
    <div className="card" style={{ marginTop: "0.75rem" }}>
      <h3 style={{ marginTop: 0 }}>Local app channel</h3>
      {status.running ? (
        <span className="status-badge status-badge--active">
          ✓ Active — port {status.port}
        </span>
      ) : (
        <span className="status-badge status-badge--revoked">Inactive</span>
      )}
      {error && <p className="error-text">{error}</p>}
      <div className="actions-row" style={{ marginTop: "0.75rem" }}>
        {status.running ? (
          <button onClick={stop}>Stop</button>
        ) : (
          <button onClick={start}>Start</button>
        )}
      </div>
    </div>
  );
}

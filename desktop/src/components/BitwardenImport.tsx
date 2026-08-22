import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useBitwardenImport } from "../hooks/useBitwardenImport";

export function BitwardenImport({ onImported }: { onImported: () => void }) {
  const { t } = useTranslation();
  const {
    stage,
    error,
    rows,
    skipped,
    pickFile,
    submitPassword,
    toggleSelected,
    setAction,
    confirmImport,
    reset,
  } = useBitwardenImport(onImported);

  const [password, setPassword] = useState("");

  if (stage === "idle" || stage === "error") {
    return (
      <div className="card">
        <p className="muted" style={{ marginTop: 0 }}>{t("bitwardenImport.description")}</p>
        {error && <p className="error-text">{error}</p>}
        <div className="actions-row">
          <button onClick={pickFile}>{t("bitwardenImport.chooseFileButton")}</button>
        </div>
      </div>
    );
  }

  if (stage === "needs-password") {
    return (
      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("bitwardenImport.passwordTitle")}</h3>
        <p className="muted">{t("bitwardenImport.passwordDescription")}</p>
        <div className="field">
          <label htmlFor="bitwarden-import-password">{t("bitwardenImport.passwordLabel")}</label>
          <input
            id="bitwarden-import-password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        {error && <p className="error-text">{error}</p>}
        <div className="actions-row">
          <button onClick={() => submitPassword(password)} disabled={!password.trim()}>
            {t("bitwardenImport.passwordSubmitButton")}
          </button>
          <button onClick={reset} style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)" }}>
            {t("bitwardenImport.cancelButton")}
          </button>
        </div>
      </div>
    );
  }

  if (stage === "reviewing" || stage === "importing") {
    const selectedCount = rows.filter(
      (r) => r.selected && !(r.possible_duplicate_id && r.action === "skip"),
    ).length;
    return (
      <div className="card">
        <h3 style={{ marginTop: 0 }}>{t("bitwardenImport.reviewTitle", { count: rows.length })}</h3>
        <p className="muted" style={{ marginTop: 0 }}>{t("bitwardenImport.reviewDescription")}</p>

        {rows.length === 0 && <p className="muted">{t("bitwardenImport.noItemsFound")}</p>}

        {rows.map((row, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              alignItems: "center",
              gap: "0.75rem",
              padding: "0.5rem 0",
              borderBottom: "1px solid var(--color-border)",
            }}
          >
            <input
              type="checkbox"
              checked={row.selected}
              onChange={() => toggleSelected(i)}
            />
            <div style={{ flex: 1 }}>
              <div>{row.type === "creditCard" ? row.credit_card?.label : row.site}</div>
              {row.type !== "creditCard" && (
                <div className="muted" style={{ fontSize: "0.85em" }}>{row.username}</div>
              )}
            </div>
            {row.possible_duplicate_id && (
              <select
                value={row.action}
                onChange={(e) => setAction(i, e.target.value as typeof row.action)}
                disabled={!row.selected}
              >
                <option value="skip">{t("bitwardenImport.duplicateActionSkip")}</option>
                <option value="overwrite">{t("bitwardenImport.duplicateActionOverwrite")}</option>
                <option value="new">{t("bitwardenImport.duplicateActionNew")}</option>
              </select>
            )}
          </div>
        ))}

        {skipped.length > 0 && (
          <div style={{ marginTop: "1rem" }}>
            <p className="muted" style={{ marginBottom: "0.25rem" }}>
              {t("bitwardenImport.skippedTitle", { count: skipped.length })}
            </p>
            <ul className="muted" style={{ fontSize: "0.85em", marginTop: 0 }}>
              {skipped.map((s, i) => (
                <li key={i}>{s.name} — {s.reason}</li>
              ))}
            </ul>
          </div>
        )}

        {error && <p className="error-text">{error}</p>}
        <div className="actions-row" style={{ marginTop: "1rem" }}>
          <button
            onClick={() => confirmImport()}
            disabled={selectedCount === 0 || stage === "importing"}
          >
            {stage === "importing"
              ? t("bitwardenImport.importing")
              : t("bitwardenImport.confirmButton", { count: selectedCount })}
          </button>
          <button onClick={reset} style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)" }}>
            {t("bitwardenImport.cancelButton")}
          </button>
        </div>
      </div>
    );
  }

  // stage === "done"
  return (
    <div className="card">
      <p className="muted" style={{ marginTop: 0 }}>{t("bitwardenImport.importedMessage")}</p>
      <p className="muted">{t("bitwardenImport.deleteFileReminder")}</p>
      <div className="actions-row">
        <button onClick={reset}>{t("bitwardenImport.importAnotherButton")}</button>
      </div>
    </div>
  );
}

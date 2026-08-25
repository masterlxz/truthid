import { useState } from "react";
import { useTranslation } from "react-i18next";

// Tela cheia bloqueante — mesma forma de `LocalWalletBackupGate.tsx`.
// Deliberadamente sem botão de fechar/overlay clicável: se o bloqueio está
// habilitado, essa é a única porta de entrada pro app.
export function AppLockGate({ onUnlock }: { onUnlock: (password: string) => Promise<boolean> }) {
  const { t } = useTranslation();
  const [password, setPassword] = useState("");
  const [checking, setChecking] = useState(false);
  const [error, setError] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!password || checking) return;
    setChecking(true);
    setError(false);
    const correct = await onUnlock(password);
    if (!correct) {
      setChecking(false);
      setError(true);
      setPassword("");
    }
  }

  return (
    <div className="modal-overlay">
      <form className="modal-box" onSubmit={handleSubmit}>
        <h2 className="modal-title">{t("appLockGate.title")}</h2>
        <div className="field" style={{ marginTop: "1rem" }}>
          <label htmlFor="app-lock-password">{t("appLockGate.passwordLabel")}</label>
          <input
            id="app-lock-password"
            type="password"
            autoFocus
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={checking}
          />
        </div>
        {error && <p className="error-text">{t("appLockGate.wrongPassword")}</p>}
        <div className="actions-row">
          <button type="submit" disabled={!password || checking}>
            {checking ? t("appLockGate.checking") : t("appLockGate.unlockButton")}
          </button>
        </div>
      </form>
    </div>
  );
}

import { useState } from "react";
import { useTranslation } from "react-i18next";

// Tela cheia bloqueante — mesma forma de `LocalWalletBackupGate.tsx`.
// Deliberadamente sem botão de fechar/overlay clicável: se o bloqueio está
// habilitado, essa é a única porta de entrada pro app — a única outra saída
// é o link "Esqueceu sua senha?" abaixo, que reseta o bloqueio (ver `onReset`).
export function AppLockGate({
  onUnlock,
  onReset,
}: {
  onUnlock: (password: string) => Promise<boolean>;
  onReset: () => Promise<void>;
}) {
  const { t } = useTranslation();
  const [password, setPassword] = useState("");
  const [checking, setChecking] = useState(false);
  const [errorKind, setErrorKind] = useState<"none" | "wrongPassword" | "unexpectedError">("none");
  const [confirmingReset, setConfirmingReset] = useState(false);
  const [resetting, setResetting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!password || checking) return;
    setChecking(true);
    setErrorKind("none");
    try {
      const correct = await onUnlock(password);
      if (!correct) {
        setErrorKind("wrongPassword");
        setPassword("");
      }
    } catch {
      // IPC transiente ou blob corrompido (`app_lock_verify` rejeitando em
      // vez de resolver `false`) — não é "senha errada", é um erro
      // inesperado; sem o `finally` abaixo isso travava "Verificando..."
      // pra sempre (achado real, P84).
      setErrorKind("unexpectedError");
    } finally {
      setChecking(false);
    }
  }

  async function handleReset() {
    setResetting(true);
    try {
      await onReset();
    } finally {
      setResetting(false);
      setConfirmingReset(false);
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
        {errorKind === "wrongPassword" && <p className="error-text">{t("appLockGate.wrongPassword")}</p>}
        {errorKind === "unexpectedError" && <p className="error-text">{t("appLockGate.unexpectedError")}</p>}
        <div className="actions-row">
          <button type="submit" disabled={!password || checking}>
            {checking ? t("appLockGate.checking") : t("appLockGate.unlockButton")}
          </button>
        </div>

        {!confirmingReset && (
          <button type="button" onClick={() => setConfirmingReset(true)}>
            {t("appLockGate.forgotPassword")}
          </button>
        )}

        {confirmingReset && (
          <div className="card" style={{ marginTop: "1rem" }}>
            <p className="muted">{t("appLockGate.resetExplanation")}</p>
            <div className="actions-row">
              <button type="button" onClick={handleReset} disabled={resetting}>
                {resetting ? t("appLockGate.resetting") : t("appLockGate.confirmResetButton")}
              </button>
              <button type="button" onClick={() => setConfirmingReset(false)} disabled={resetting}>
                {t("appLockGate.cancel")}
              </button>
            </div>
          </div>
        )}
      </form>
    </div>
  );
}

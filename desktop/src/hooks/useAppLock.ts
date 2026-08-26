import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

// Bloqueio opcional do app por senha própria do TruthID — espelha
// `useLocalWalletBackupGate.ts`. `isLocked` começa `null` (ainda checando)
// pra `App.tsx` evitar mostrar a tela normal por um instante antes do check
// assíncrono resolver. Uma vez desbloqueado nesta sessão, fica desbloqueado
// até o app fechar — não persiste em lugar nenhum, é "senha pra ENTRAR no
// app", não uma re-checagem constante.
export function useAppLock() {
  const [isLocked, setIsLocked] = useState<boolean | null>(null);

  useEffect(() => {
    invoke<boolean>("app_lock_is_enabled")
      .then(setIsLocked)
      .catch(() => setIsLocked(false));
  }, []);

  const unlock = useCallback(async (password: string) => {
    const correct = await invoke<boolean>("app_lock_verify", { password });
    if (correct) setIsLocked(false);
    return correct;
  }, []);

  // Único jeito de sair do AppLockGate sem a senha — pra quem esqueceu a
  // senha ou tem o blob armazenado corrompido. Sem confirmação de senha (não
  // há uma pra checar); só remove o gate, não afeta Vault/identidade.
  const reset = useCallback(async () => {
    await invoke("app_lock_reset");
    setIsLocked(false);
  }, []);

  return { isLocked, unlock, reset };
}

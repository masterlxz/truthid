import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

// Gate global de backup obrigatório da wallet local (P78, pedaço 1) — a
// chave já existe no keyring assim que `local_wallet_generate` roda; se o
// app fechar antes do usuário confirmar/exportar o backup, precisamos pegar
// isso na reabertura (o fluxo de criação sozinho, em ConnectLocalWallet.tsx,
// não cobre esse caso). `needsBackup` começa `null` (ainda checando) pra
// App.tsx evitar mostrar a tela normal por um instante antes do check
// assíncrono resolver.
export function useLocalWalletBackupGate() {
  const [needsBackup, setNeedsBackup] = useState<boolean | null>(null);

  const check = useCallback(() => {
    Promise.all([
      invoke<boolean>("local_wallet_exists").catch(() => false),
      invoke<boolean>("local_wallet_backup_confirmed").catch(() => false),
    ]).then(([exists, confirmed]) => setNeedsBackup(exists && !confirmed));
  }, []);

  useEffect(check, [check]);

  return { needsBackup, markConfirmed: check };
}

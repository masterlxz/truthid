import { useCallback, useEffect, useState } from "react";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";

export type UpdateStatus = "idle" | "available" | "downloading" | "ready" | "error";

export function useUpdateCheck() {
  const [status, setStatus] = useState<UpdateStatus>("idle");
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);
  const [pendingUpdate, setPendingUpdate] = useState<Update | null>(null);

  useEffect(() => {
    let cancelled = false;
    check()
      .then((result) => {
        if (cancelled || !result) return;
        setPendingUpdate(result);
        setUpdateVersion(result.version);
        setStatus("available");
      })
      // Falha silenciosa de propósito (rede indisponível, endpoint fora do
      // ar, etc.) — mesmo comportamento do checker anterior, checar por
      // atualização nunca deve interromper o uso normal do app.
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  const installUpdate = useCallback(async () => {
    if (!pendingUpdate) return;
    setStatus("downloading");
    try {
      await pendingUpdate.downloadAndInstall();
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, [pendingUpdate]);

  // Passo separado de `installUpdate` de propósito — reiniciar fecha
  // qualquer trabalho em andamento no app (assinatura de identidade,
  // wallet), então quem usa o hook decide o momento certo, não o download
  // em si.
  const restartNow = useCallback(() => {
    void relaunch();
  }, []);

  return { status, updateVersion, installUpdate, restartNow };
}

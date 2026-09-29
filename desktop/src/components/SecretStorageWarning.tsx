import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";

// Aviso quando o keyring do SO falhou e algum segredo (chave do device, do
// vault, wallet) caiu no fallback em arquivo de texto plano em ~/.truthid —
// antes o fallback era silencioso (P95, revisão de segurança do winget-pkgs).
export function SecretStorageWarning() {
  const { t } = useTranslation();
  const [active, setActive] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const fallback = await invoke<boolean>("secret_storage_fallback_active");
        if (!cancelled) setActive(fallback);
      } catch {
        // Sem resposta do backend, não mostra aviso (não bloqueia a tela).
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (!active) return null;

  return (
    <div className="card" role="alert" style={{ borderColor: "var(--danger, #c0392b)" }}>
      <strong>{t("secretStorageWarning.title")}</strong>
      <p style={{ lineHeight: "1.5", marginBottom: 0 }}>{t("secretStorageWarning.body")}</p>
    </div>
  );
}

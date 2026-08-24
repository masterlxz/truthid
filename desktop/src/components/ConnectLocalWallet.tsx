import { useState } from "react";
import { useTranslation } from "react-i18next";
import { invoke } from "@tauri-apps/api/core";
import { useConnect } from "wagmi";
import { localWallet } from "../connectors/localWallet";
import { LocalWalletBackupGate } from "./LocalWalletBackupGate";

type Phase = "intro" | "created" | "connecting";

// Wallet local embutida (P78, pedaço 1) — cria e conecta uma chave gerada
// só neste device, sem Ledger/Trezor/WalletConnect. Espelha a estrutura de
// ConnectLedger.tsx/ConnectTrezor.tsx, mas sem detecção de hardware: gerar a
// chave é instantâneo, o passo que precisa de atenção do usuário é o gate de
// backup (LocalWalletBackupGate), não um dispositivo físico.
export function ConnectLocalWallet({ onBack }: { onBack: () => void }) {
  const { t } = useTranslation();
  const { connectAsync } = useConnect();
  const [phase, setPhase] = useState<Phase>("intro");
  const [address, setAddress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleCreate() {
    setError(null);
    try {
      const addr = await invoke<string>("local_wallet_generate");
      setAddress(addr);
      setPhase("created");
    } catch (e) {
      setError(String(e));
    }
  }

  async function handleBackupConfirmed() {
    setPhase("connecting");
    try {
      await connectAsync({ connector: localWallet });
    } catch (e) {
      setError(String(e));
      setPhase("created");
    }
  }

  return (
    <div className="local-wallet-connect">
      <button className="back-btn" onClick={onBack}>
        ← {t("connectLocalWallet.back")}
      </button>

      {phase === "intro" && (
        <>
          <h2 className="local-wallet-connect-title">{t("connectLocalWallet.intro.title")}</h2>
          <div className="local-wallet-error-box">{t("connectLocalWallet.intro.warning")}</div>
          {error && <div className="local-wallet-error-box">{error}</div>}
          <button onClick={handleCreate}>{t("connectLocalWallet.intro.createButton")}</button>
        </>
      )}

      {(phase === "created" || phase === "connecting") && address && (
        <>
          <h2 className="local-wallet-connect-title">{t("connectLocalWallet.created.title")}</h2>
          <div className="card">
            <p className="muted" style={{ marginTop: 0 }}>{t("connectLocalWallet.created.addressLabel")}</p>
            <code>{address}</code>
            <p className="muted">{t("connectLocalWallet.created.fundingHint")}</p>
          </div>

          {error && <div className="local-wallet-error-box">{error}</div>}

          {phase === "connecting" ? (
            <p className="muted">{t("connectLocalWallet.connecting")}</p>
          ) : (
            <LocalWalletBackupGate onConfirmed={handleBackupConfirmed} inline />
          )}
        </>
      )}
    </div>
  );
}

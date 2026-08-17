import { useState, useEffect, useMemo, useCallback } from "react";
import { useTranslation } from "react-i18next";
import { useAccount, useReadContract, useSwitchChain, useDisconnect } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { base } from "wagmi/chains";
import type { Address } from "viem";
import { ConnectWallet } from "./components/ConnectWallet";
import { CreateIdentity } from "./components/CreateIdentity";
import { ManageDevices } from "./components/ManageDevices";
import { ActiveSessions } from "./components/ActiveSessions";
import { QuickLogin } from "./components/QuickLogin";
import { DonateModal } from "./components/DonateModal";
import { VaultManagement } from "./components/VaultManagement";
import { SmartAccountDashboard } from "./components/SmartAccountDashboard";
import { IdentityProvider } from "./contexts/IdentityContext";
import { WalletModalContext } from "./contexts/WalletModalContext";
import { useStoredUsername } from "./hooks/useStoredUsername";
import { useUpdateCheck } from "./hooks/useUpdateCheck";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "./config/contracts";
import {
  TRUTHID_ACCOUNT_FACTORY_ADDRESS,
  FACTORY_IMMUTABLES,
} from "./config/truthidAccount";
import { computeSmartAccountAddressSync } from "./utils/computeSmartAccountAddress";
import { SignRequestModal } from "./components/SignRequestModal";
import { SignMessageModal } from "./components/SignMessageModal";
import { PinApprovalModal } from "./components/PinApprovalModal";
import { VaultEditApprovalModal } from "./components/VaultEditApprovalModal";
import { AutofillAddressApprovalModal } from "./components/AutofillAddressApprovalModal";
import { AutofillCreditCardApprovalModal } from "./components/AutofillCreditCardApprovalModal";
import { GuardianManagement } from "./components/GuardianManagement";
import "./App.css";

type Tab = "dashboard" | "devices" | "sessions" | "vault" | "recovery";

function LogoIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 28 28" fill="none">
      <path
        d="M14 2L24 8V20L14 26L4 20V8L14 2Z"
        fill="none"
        stroke="#4DD0E1"
        strokeWidth="1.5"
      />
      <path
        d="M14 7L20 10.5V17.5L14 21L8 17.5V10.5L14 7Z"
        fill="rgba(77,208,225,0.15)"
        stroke="#4DD0E1"
        strokeWidth="1"
      />
      <path d="M14 11V17M11 14H17" stroke="#4DD0E1" strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  );
}

function App() {
  const { t } = useTranslation();
  const { isConnected, address, chainId } = useAccount();
  const { disconnect } = useDisconnect();
  const [activeTab, setActiveTab] = useState<Tab>("dashboard");
  const [loginOpen, setLoginOpen] = useState(false);
  const [connectModalOpen, setConnectModalOpen] = useState(false);
  const [donateOpen, setDonateOpen] = useState(false);
  const queryClient = useQueryClient();

  const { username: storedUsername, save: saveUsername, clear: clearUsername } = useStoredUsername();
  const { updateVersion, updateUrl } = useUpdateCheck();
  const [updateDismissed, setUpdateDismissed] = useState(false);

  const isWrongNetwork = isConnected && chainId !== base.id;
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  // Nem ConnectWallet nem ConnectLedger fecham o modal sozinhos depois de
  // conectar com sucesso — sem isso, a UI ficava parada na tela de conexão
  // mesmo com a wallet já conectada (só um refresh/clique manual revelava
  // que tinha funcionado). Centralizado aqui cobre os dois conectores
  // (WalletConnect e Ledger) e os dois pontos de entrada do modal (topbar e
  // qualquer ação que chame openConnectModal, ex: revoke/pair sem wallet).
  useEffect(() => {
    if (isConnected) {
      setConnectModalOpen(false);
      setLoginOpen(false);
    }
  }, [isConnected]);

  const smartAccountAddress = useMemo<Address | null>(() => {
    if (!address) return null;
    try {
      return computeSmartAccountAddressSync(
        address,
        TRUTHID_ACCOUNT_FACTORY_ADDRESS,
        FACTORY_IMMUTABLES,
      );
    } catch {
      return null;
    }
  }, [address]);

  const {
    data: onChainUsername,
    isLoading: isLoadingUsername,
    isError: isIdentityError,
    error: identityError,
    refetch: refetchIdentity,
  } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getUsernameByController",
    args: smartAccountAddress ? [smartAccountAddress] : undefined,
    query: { enabled: !!smartAccountAddress && !isWrongNetwork },
  });

  // Save on-chain verified username to localStorage whenever we read it
  useEffect(() => {
    if (onChainUsername) saveUsername(onChainUsername as string);
  }, [onChainUsername]);

  // Displayed username: on-chain (verified) takes priority, falls back to localStorage
  const displayUsername = (isConnected && !isWrongNetwork && (onChainUsername as string | undefined)) || storedUsername;

  // Only block rendering with a loading state when we have no cached identity to show
  const isLoadingIdentity = isConnected && !isWrongNetwork && isLoadingUsername && !storedUsername;

  // Precisam rodar incondicionalmente, antes de qualquer return — chamá-los
  // só no branch do shell principal (abaixo do early return de "sem
  // identidade") violava a regra de hooks (contagem de hooks mudando entre
  // renders conforme `displayUsername`/`isConnected`), causando "Rendered
  // more hooks than during the previous render" assim que o estado mudava de
  // "sem identidade" pra "com identidade" (achado real, Sessão 31 do
  // Practice Valuation, ao testar o canal /sign-request contra este app).
  const openConnectModal = useCallback(() => setConnectModalOpen(true), []);
  const walletModalContextValue = useMemo(() => ({ openConnectModal }), [openConnectModal]);

  // ── No identity at all → full-screen login ───────────────────────────────
  // SignRequestModal fica montado nos dois caminhos de retorno (aqui e no
  // shell principal abaixo) porque um pedido de assinatura pode chegar a
  // qualquer momento, inclusive antes do usuário conectar a wallet.
  if (!displayUsername && !isConnected) {
    return (
      <>
        <SignRequestModal smartAccountAddress={smartAccountAddress} />
        <SignMessageModal />
        <PinApprovalModal />
        <VaultEditApprovalModal smartAccountAddress={smartAccountAddress} />
        <AutofillAddressApprovalModal />
        <AutofillCreditCardApprovalModal />
        <ConnectWallet />
      </>
    );
  }

  function handleLogout() {
    clearUsername();
    disconnect();
  }

  // ── App shell ─────────────────────────────────────────────────────────────
  return (
    <WalletModalContext.Provider value={walletModalContextValue}>
      <SignRequestModal smartAccountAddress={smartAccountAddress} />
      <SignMessageModal />
      <PinApprovalModal />
      <VaultEditApprovalModal smartAccountAddress={smartAccountAddress} />
      <AutofillAddressApprovalModal />
      <AutofillCreditCardApprovalModal />
      <div className="app-shell">
        <header className="topbar">
          <div className="topbar-left">
            <LogoIcon />
            TruthID
          </div>
          <div className="topbar-right">
            {displayUsername && (
              <button className="topbar-btn" onClick={() => setLoginOpen(true)}>
                {t("app.topbar.login")}
              </button>
            )}
            {displayUsername && (
              <span className="topbar-username">@{displayUsername}</span>
            )}
            {displayUsername && (
              <button
                className="topbar-btn"
                onClick={() => queryClient.invalidateQueries()}
                title={t("app.topbar.refresh")}
              >
                ↻
              </button>
            )}
            {isConnected ? (
              <button
                className="topbar-btn topbar-btn-danger"
                onClick={() => disconnect()}
                title={t("app.topbar.disconnectWallet")}
              >
                {t("app.topbar.disconnectWallet")}
              </button>
            ) : (
              <button
                className="topbar-btn"
                onClick={() => setConnectModalOpen(true)}
              >
                {t("app.topbar.connectWallet")}
              </button>
            )}
            <button
              className="topbar-btn"
              onClick={() => setDonateOpen(true)}
              title={t("app.topbar.donate")}
            >
              ♥
            </button>
            <button
              className="topbar-btn topbar-btn-danger"
              onClick={handleLogout}
              title={t("app.topbar.logoutTitle")}
            >
              {t("app.topbar.logout")}
            </button>
          </div>
        </header>

        {updateVersion && !updateDismissed && (
          <div className="update-banner">
            <span>⬆ {t("app.updateBanner.available", { version: updateVersion })}</span>
            <a href={updateUrl} target="_blank" rel="noreferrer" className="update-banner-link">
              {t("app.updateBanner.download")}
            </a>
            <button className="update-banner-dismiss" onClick={() => setUpdateDismissed(true)}>
              ✕
            </button>
          </div>
        )}

        <main className="main-content">
          {isWrongNetwork && (
            <div className="card">
              <p>{t("app.wrongNetwork.message")}</p>
              <button onClick={() => switchChain({ chainId: base.id })} disabled={isSwitching}>
                {isSwitching ? t("app.wrongNetwork.switching") : t("app.wrongNetwork.switchButton")}
              </button>
            </div>
          )}

          {!isWrongNetwork && isLoadingIdentity && (
            <p className="muted">{t("app.loading")}</p>
          )}

          {!isWrongNetwork && !isLoadingIdentity && isIdentityError && !storedUsername && (
            <div className="card">
              <p className="error-text">
                {t("app.identityError.message", { error: identityError?.message?.split("\n")[0] })}
              </p>
              <button onClick={() => refetchIdentity()}>{t("app.identityError.retry")}</button>
            </div>
          )}

          {/* First-time user: connected, no on-chain identity, nothing in localStorage */}
          {isConnected && !isWrongNetwork && !isLoadingIdentity && !onChainUsername && !storedUsername && smartAccountAddress && (
            <CreateIdentity smartAccountAddress={smartAccountAddress} />
          )}

          {displayUsername && (
            <IdentityProvider username={displayUsername} smartAccountAddress={smartAccountAddress}>
              <nav className="tabs">
                <button
                  onClick={() => setActiveTab("dashboard")}
                  disabled={activeTab === "dashboard"}
                >
                  Dashboard
                </button>
                <button
                  onClick={() => setActiveTab("devices")}
                  disabled={activeTab === "devices"}
                >
                  Devices
                </button>
                <button
                  onClick={() => setActiveTab("sessions")}
                  disabled={activeTab === "sessions"}
                >
                  Active Sessions
                </button>
                <button
                  onClick={() => setActiveTab("vault")}
                  disabled={activeTab === "vault"}
                >
                  Vault
                </button>
                <button
                  onClick={() => setActiveTab("recovery")}
                  disabled={activeTab === "recovery"}
                >
                  Recovery
                </button>
              </nav>

              {activeTab === "dashboard" && <SmartAccountDashboard />}
              {activeTab === "devices" && <ManageDevices />}
              {activeTab === "sessions" && <ActiveSessions />}
              {activeTab === "vault" && <VaultManagement />}
              {activeTab === "recovery" && <GuardianManagement />}
            </IdentityProvider>
          )}
        </main>

        {loginOpen && (
          <div className="modal-overlay" onClick={() => setLoginOpen(false)}>
            <div className="modal-box" onClick={(e) => e.stopPropagation()}>
              <div className="modal-header">
                <h2 className="modal-title">Desktop Login</h2>
                <button className="modal-close" onClick={() => setLoginOpen(false)}>✕</button>
              </div>
              <QuickLogin />
            </div>
          </div>
        )}

        {connectModalOpen && (
          <div className="modal-overlay" onClick={() => setConnectModalOpen(false)}>
            <div className="modal-box" onClick={(e) => e.stopPropagation()}>
              <ConnectWallet asModal onClose={() => setConnectModalOpen(false)} />
            </div>
          </div>
        )}

        {donateOpen && (
          <div className="modal-overlay" onClick={() => setDonateOpen(false)}>
            <div className="modal-box" onClick={(e) => e.stopPropagation()}>
              <div className="modal-header">
                <h2 className="modal-title">Donate to TruthID</h2>
                <button className="modal-close" onClick={() => setDonateOpen(false)}>✕</button>
              </div>
              <DonateModal />
            </div>
          </div>
        )}
      </div>
    </WalletModalContext.Provider>
  );
}

export default App;

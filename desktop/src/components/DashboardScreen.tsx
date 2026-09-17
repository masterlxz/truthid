import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useIdentity } from "../contexts/IdentityContext";
import { SmartAccountDashboard } from "./SmartAccountDashboard";
import { ArweaveDashboard } from "./ArweaveDashboard";

type DashboardView = "eth" | "arweave";

/** Container da aba "Dashboard" (P67) — toggle entre a visão ETH (smart
 * account, inalterada) e a visão Arweave (wallet de storage, nova). */
export function DashboardScreen() {
  const { t } = useTranslation();
  const { username } = useIdentity();
  const [view, setView] = useState<DashboardView>("eth");

  return (
    <div>
      <h2>@{username}</h2>
      <nav className="segmented" style={{ marginBottom: "1.25rem" }}>
        <button onClick={() => setView("eth")} disabled={view === "eth"}>
          {t("dashboardScreen.toggle.eth")}
        </button>
        <button onClick={() => setView("arweave")} disabled={view === "arweave"}>
          {t("dashboardScreen.toggle.arweave")}
        </button>
      </nav>
      {view === "eth" ? <SmartAccountDashboard /> : <ArweaveDashboard />}
    </div>
  );
}

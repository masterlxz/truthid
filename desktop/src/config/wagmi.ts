import { createConfig, http, fallback } from "wagmi";
import { base } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { ledger } from "../connectors/ledger";

// Project ID público do Reown/WalletConnect Cloud — identifica o app, não dá
// acesso a nada (não é segredo). Necessário pro fluxo de QR code, já que o
// Tauri usa WebKitGTK como webview e não suporta extensões de navegador tipo
// MetaMask — o conector "injected" nunca encontra um provider dentro do app
// empacotado, só funciona em desenvolvimento via `npm run dev` num browser normal.
const WALLETCONNECT_PROJECT_ID = "ecf672e1e9d165bb65017b793e80c0af";

export const config = createConfig({
  storage: null, // don't persist connector state — reconnect is manual
  chains: [base],
  connectors: [
    injected(),
    walletConnect({ projectId: WALLETCONNECT_PROJECT_ID, showQrModal: true }),
    ledger,
  ],
  transports: {
    // fallback: tenta o primeiro RPC, se falhar vai pro próximo
    [base.id]: fallback([
      http("https://mainnet.base.org"),
      http("https://base-rpc.publicnode.com"),
      http("https://base.drpc.org"),
    ]),
  },
});

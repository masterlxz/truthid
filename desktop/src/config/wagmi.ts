import { createConfig, http, fallback } from "wagmi";
import { base } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [base],
  connectors: [injected()],
  transports: {
    // fallback: tenta o primeiro RPC, se falhar vai pro próximo
    [base.id]: fallback([
      http("https://mainnet.base.org"),
      http("https://base-rpc.publicnode.com"),
      http("https://base.drpc.org"),
    ]),
  },
});

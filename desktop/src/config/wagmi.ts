import { createConfig, http, fallback } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [baseSepolia],
  connectors: [injected()],
  transports: {
    // fallback: tenta o primeiro RPC, se falhar vai pro próximo
    [baseSepolia.id]: fallback([
      http("https://sepolia.base.org"),
      http("https://base-sepolia-rpc.publicnode.com"),
      http("https://base-sepolia.blockpi.network/v1/rpc/public"),
    ]),
  },
});

import { createContext, useContext } from "react";

interface WalletModalContextValue {
  openConnectModal: () => void;
}

export const WalletModalContext = createContext<WalletModalContextValue>({
  openConnectModal: () => {},
});

export function useWalletModal() {
  return useContext(WalletModalContext);
}

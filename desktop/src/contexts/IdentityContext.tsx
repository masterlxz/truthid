import { createContext, useContext, useMemo, type ReactNode } from "react";
import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "../config/contracts";

interface IdentityContextValue {
  username: string;
  identityId: bigint | undefined;
  smartAccountAddress: Address | null;
}

const IdentityContext = createContext<IdentityContextValue | null>(null);

export function IdentityProvider({
  username,
  smartAccountAddress,
  children,
}: {
  username: string;
  smartAccountAddress: Address | null;
  children: ReactNode;
}) {
  const { data: identity } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getIdentity",
    args: [username],
  });

  return (
    <IdentityContext.Provider value={useMemo(() => ({ username, identityId: identity?.id, smartAccountAddress }), [username, identity?.id, smartAccountAddress])}>
      {children}
    </IdentityContext.Provider>
  );
}

export function useIdentity(): IdentityContextValue {
  const ctx = useContext(IdentityContext);
  if (!ctx) throw new Error("useIdentity must be used inside IdentityProvider");
  return ctx;
}

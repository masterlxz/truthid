import { createContext, useContext, type ReactNode } from "react";
import { useReadContract } from "wagmi";
import { IDENTITY_REGISTRY_ADDRESS, IDENTITY_REGISTRY_ABI } from "../config/contracts";

interface IdentityContextValue {
  username: string;
  identityId: bigint | undefined;
}

const IdentityContext = createContext<IdentityContextValue | null>(null);

export function IdentityProvider({ username, children }: { username: string; children: ReactNode }) {
  const { data: identity } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getIdentity",
    args: [username],
  });

  return (
    <IdentityContext.Provider value={{ username, identityId: identity?.id }}>
      {children}
    </IdentityContext.Provider>
  );
}

export function useIdentity(): IdentityContextValue {
  const ctx = useContext(IdentityContext);
  if (!ctx) throw new Error("useIdentity must be used inside IdentityProvider");
  return ctx;
}

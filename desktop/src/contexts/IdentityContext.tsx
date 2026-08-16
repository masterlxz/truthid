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
  smartAccountAddress: walletDerivedAddress,
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

  // P52: `controller` já é o endereço da smart account (gravado como tal na
  // criação da identidade, ver CreateIdentity.tsx) e vem de uma leitura
  // on-chain que só depende do `username` em cache local — funciona sem
  // nenhuma wallet conectada nesta sessão. Preferir isso ao endereço derivado
  // do CREATE2 (`walletDerivedAddress`, que exige `useAccount().address`
  // populado) é o que faz caminhos "sem Ledger" (ex: publicar o vault via
  // device key) funcionarem de fato sem Ledger — antes, sem wallet conectada,
  // `smartAccountAddress` ficava `null` e esses caminhos falhavam com
  // "Nenhuma identidade carregada" mesmo com a identidade já resolvida.
  const smartAccountAddress =
    (identity?.exists ? (identity.controller as Address) : undefined) || walletDerivedAddress;

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

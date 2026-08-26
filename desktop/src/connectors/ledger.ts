import { invoke } from "@tauri-apps/api/core";
import { custom, getAddress, serializeTransaction, type Hex, type SerializeTransactionFn, type TransactionSerializable } from "viem";
import { createConnector } from "wagmi";
import { createEvmProviderRequest, parseRsvSignature, toError } from "./evmProviderShared";

// Exportado separado do connector porque `createConnector` devolve a
// função-fábrica tipada genericamente — ela não expõe `.id` em tempo de
// tipagem antes de ser resolvida pela wagmi (ver uso em ConnectWallet.tsx).
export const LEDGER_CONNECTOR_ID = "ledger";

let cachedAddress: Hex | null = null;
let cachedAccountIndex: number = 0;

export function setLedgerAccountIndex(index: number) {
  cachedAccountIndex = index;
}

async function signTransaction(
  transaction: TransactionSerializable,
  options?: { serializer?: SerializeTransactionFn<TransactionSerializable> },
): Promise<Hex> {
  const serializer = options?.serializer ?? serializeTransaction;
  const unsignedTxHex = serializer(transaction) as Hex;
  try {
    const sigHex = await invoke<string>("sign_ledger_transaction", {
      unsignedTxHex,
      accountIndex: cachedAccountIndex,
    });
    return serializer(transaction, parseRsvSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

/// Assina uma mensagem via `personal_sign` (EIP-191) com a Ledger — usado
/// pelo consentimento de `createIdentity` (débito #17). `messageHex` chega
/// já em hex vindo do `request()` abaixo (viem já normaliza string/`{raw}`
/// pra hex antes de montar a chamada `personal_sign`, então não precisa de
/// normalização adicional aqui). O retorno do lado Rust já vem no formato
/// "0x" + r + s + v — o mesmo formato que `personal_sign` deve devolver.
async function signPersonalMessage(messageHex: Hex): Promise<Hex> {
  try {
    return (await invoke<string>("sign_ledger_personal_message", {
      messageHex,
      accountIndex: cachedAccountIndex,
    })) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

export const ledger = createConnector((config) => ({
  id: LEDGER_CONNECTOR_ID,
  name: "Ledger",
  type: "ledger",

  // `withCapabilities` (ERC-5792, batch de chamadas) não é suportado por
  // este conector — nada no app usa isso hoje. O cast no retorno é porque
  // o tipo da wagmi é condicional sobre esse parâmetro genérico, e o TS
  // não consegue provar estaticamente que a forma simples (sem capabilities)
  // é o caso coberto aqui.
  async connect<withCapabilities extends boolean = false>({
    chainId,
  }: {
    chainId?: number | undefined;
    isReconnecting?: boolean | undefined;
    withCapabilities?: withCapabilities | boolean | undefined;
  } = {}) {
    const found = await invoke<string>("get_ledger_address", { accountIndex: cachedAccountIndex });
    cachedAddress = getAddress(found);
    const resolvedChainId = chainId ?? config.chains[0].id;

    config.emitter.emit("connect", { accounts: [cachedAddress], chainId: resolvedChainId });

    return { accounts: [cachedAddress], chainId: resolvedChainId } as unknown as {
      accounts: withCapabilities extends true
        ? readonly { address: Hex; capabilities: Record<string, unknown> }[]
        : readonly Hex[];
      chainId: number;
    };
  },

  async disconnect() {
    cachedAddress = null;
    cachedAccountIndex = 0;
    config.emitter.emit("disconnect");
  },

  async getAccounts() {
    if (!cachedAddress) throw new Error("Ledger not connected.");
    return [cachedAddress];
  },

  async getChainId() {
    return config.chains[0].id;
  },

  // Nunca reconecta sozinha: a Ledger exige replugar/desbloquear o
  // dispositivo a cada sessão, então não há "sessão salva" pra retomar.
  async isAuthorized() {
    return false;
  },

  onAccountsChanged(accounts) {
    if (accounts.length === 0) config.emitter.emit("disconnect");
  },

  onChainChanged() {
    // só há uma chain configurada (Base) — nada a fazer.
  },

  async onDisconnect() {
    cachedAddress = null;
    config.emitter.emit("disconnect");
  },

  async getProvider({ chainId } = {}) {
    const chain = config.chains.find((c) => c.id === chainId) ?? config.chains[0];
    const transport = config.transports?.[chain.id];

    const request = createEvmProviderRequest({
      chain,
      transport,
      walletLabel: "Ledger",
      notConnectedMessage: "Ledger not connected.",
      getCachedAddress: () => cachedAddress,
      signTransaction,
      signPersonalMessage,
    });

    return custom({ request })({ retryCount: 0 });
  },
}));

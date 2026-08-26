import { invoke } from "@tauri-apps/api/core";
import { custom, getAddress, numberToHex, serializeTransaction, type Hex, type SerializeTransactionFn, type TransactionSerializable } from "viem";
import { createConnector } from "wagmi";
import { createEvmProviderRequest, parseRsvSignature, toError } from "./evmProviderShared";

// Exportado separado do connector porque `createConnector` devolve a
// função-fábrica tipada genericamente — ela não expõe `.id` em tempo de
// tipagem antes de ser resolvida pela wagmi (ver uso em ConnectWallet.tsx).
export const TREZOR_CONNECTOR_ID = "trezor";

let cachedAddress: Hex | null = null;
let cachedAccountIndex: number = 0;

export function setTrezorAccountIndex(index: number) {
  cachedAccountIndex = index;
}

/// Diferente da Ledger (recebe a transação já serializada em RLP e não
/// decodifica nada), a Trezor exige os campos decompostos — o comando Rust
/// `sign_trezor_transaction` recebe cada campo separado. Escopo v1: só
/// transações EIP-1559 (único tipo usado nesta app, chain única é Base).
async function signTransaction(
  transaction: TransactionSerializable,
  options?: { serializer?: SerializeTransactionFn<TransactionSerializable> },
): Promise<Hex> {
  const serializer = options?.serializer ?? serializeTransaction;

  if (transaction.type !== "eip1559" || transaction.maxFeePerGas === undefined) {
    throw new Error("Trezor: only EIP-1559 transactions are supported by this connector.");
  }

  try {
    const sigHex = await invoke<string>("sign_trezor_transaction", {
      accountIndex: cachedAccountIndex,
      chainId: transaction.chainId,
      nonce: transaction.nonce ?? 0,
      to: transaction.to ?? "",
      valueHex: numberToHex(transaction.value ?? 0n),
      dataHex: transaction.data ?? "0x",
      gasLimitHex: numberToHex(transaction.gas ?? 0n),
      maxFeePerGasHex: numberToHex(transaction.maxFeePerGas),
      maxPriorityFeePerGasHex: numberToHex(transaction.maxPriorityFeePerGas ?? 0n),
    });
    return serializer(transaction, parseRsvSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

/// Assina uma mensagem via `personal_sign` (EIP-191) com a Trezor — usado
/// pelo consentimento de `createIdentity` (mesmo papel do conector da
/// Ledger). O retorno do lado Rust já vem no formato "0x" + r + s + v.
async function signPersonalMessage(messageHex: Hex): Promise<Hex> {
  try {
    return (await invoke<string>("sign_trezor_personal_message", {
      messageHex,
      accountIndex: cachedAccountIndex,
    })) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

export const trezor = createConnector((config) => ({
  id: TREZOR_CONNECTOR_ID,
  name: "Trezor",
  type: "trezor",

  async connect<withCapabilities extends boolean = false>({
    chainId,
  }: {
    chainId?: number | undefined;
    isReconnecting?: boolean | undefined;
    withCapabilities?: withCapabilities | boolean | undefined;
  } = {}) {
    const found = await invoke<string>("get_trezor_address", { accountIndex: cachedAccountIndex });
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
    if (!cachedAddress) throw new Error("Trezor not connected.");
    return [cachedAddress];
  },

  async getChainId() {
    return config.chains[0].id;
  },

  // Nunca reconecta sozinha: a Trezor exige replugar/desbloquear o
  // dispositivo a cada sessão, mesmo comportamento da Ledger.
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
      walletLabel: "Trezor",
      notConnectedMessage: "Trezor not connected.",
      getCachedAddress: () => cachedAddress,
      signTransaction,
      signPersonalMessage,
    });

    return custom({ request })({ retryCount: 0 });
  },
}));

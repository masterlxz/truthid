import { invoke } from "@tauri-apps/api/core";
import { custom, getAddress, serializeTransaction, type Hex, type SerializeTransactionFn, type TransactionSerializable } from "viem";
import { createConnector } from "wagmi";
import { createEvmProviderRequest, parseRsvSignature, toError } from "./evmProviderShared";

// Wallet local embutida (P78, pedaço 1) — chave secp256k1 gerada e guardada
// só neste device (ver `local_wallet.rs`), sem hardware/app externo. Espelha
// `ledger.ts` (mesma forma: tx serializada em RLP, Rust decide o hash e
// assina), só que a assinatura acontece direto em Rust em vez de via HID/USB.
export const LOCAL_WALLET_CONNECTOR_ID = "localWallet";

let cachedAddress: Hex | null = null;

async function signTransaction(
  transaction: TransactionSerializable,
  options?: { serializer?: SerializeTransactionFn<TransactionSerializable> },
): Promise<Hex> {
  const serializer = options?.serializer ?? serializeTransaction;
  const unsignedTxHex = serializer(transaction) as Hex;
  try {
    const sigHex = await invoke<string>("sign_local_wallet_transaction", { unsignedTxHex });
    return serializer(transaction, parseRsvSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

/// Assina uma mensagem via `personal_sign` (EIP-191) com a chave local —
/// usado pelo consentimento de `createIdentity` e pela derivação da vault
/// key. `messageHex` chega já em hex vindo do `request()` abaixo (viem já
/// normaliza string/`{raw}` pra hex antes de montar a chamada `personal_sign`).
async function signPersonalMessage(messageHex: Hex): Promise<Hex> {
  try {
    return (await invoke<string>("sign_local_wallet_personal_message", {
      messageHex,
    })) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

export const localWallet = createConnector((config) => ({
  id: LOCAL_WALLET_CONNECTOR_ID,
  name: "Local Wallet",
  type: "localWallet",

  async connect<withCapabilities extends boolean = false>({
    chainId,
  }: {
    chainId?: number | undefined;
    isReconnecting?: boolean | undefined;
    withCapabilities?: withCapabilities | boolean | undefined;
  } = {}) {
    const found = await invoke<string>("local_wallet_address");
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
    config.emitter.emit("disconnect");
  },

  async getAccounts() {
    if (!cachedAddress) throw new Error("Local wallet not connected.");
    return [cachedAddress];
  },

  async getChainId() {
    return config.chains[0].id;
  },

  // Diferente de Ledger/Trezor: não há hardware pra replugar — se a chave já
  // existe na custódia local (keyring/fallback em arquivo), a wallet pode
  // reconectar sozinha.
  async isAuthorized() {
    try {
      return await invoke<boolean>("local_wallet_exists");
    } catch {
      return false;
    }
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
      walletLabel: "Local Wallet",
      notConnectedMessage: "Local wallet not connected.",
      getCachedAddress: () => cachedAddress,
      signTransaction,
      signPersonalMessage,
    });

    return custom({ request })({ retryCount: 0 });
  },
}));

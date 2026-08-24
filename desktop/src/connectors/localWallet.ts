import { invoke } from "@tauri-apps/api/core";
import {
  createWalletClient,
  custom,
  getAddress,
  numberToHex,
  serializeTransaction,
  type Hex,
  type SerializeTransactionFn,
  type TransactionSerializable,
} from "viem";
import { toAccount } from "viem/accounts";
import { createConnector } from "wagmi";

// Wallet local embutida (P78, pedaço 1) — chave secp256k1 gerada e guardada
// só neste device (ver `local_wallet.rs`), sem hardware/app externo. Espelha
// `ledger.ts` (mesma forma: tx serializada em RLP, Rust decide o hash e
// assina), só que a assinatura acontece direto em Rust em vez de via HID/USB.
export const LOCAL_WALLET_CONNECTOR_ID = "localWallet";

let cachedAddress: Hex | null = null;

/// Assinatura combinada que o lado Rust devolve: "0x" + r (32 bytes) + s
/// (32 bytes) + v (1 byte, convenção 27/28) — mesmo formato de
/// `parseLedgerSignature`/`parseTrezorSignature`.
function parseLocalWalletSignature(sigHex: string) {
  const r = `0x${sigHex.slice(2, 66)}` as Hex;
  const s = `0x${sigHex.slice(66, 130)}` as Hex;
  const v = Number.parseInt(sigHex.slice(130, 132), 16);
  return { r, s, yParity: v - 27 };
}

// Tauri's invoke() rejects with a plain string when Rust returns Err(...).
// JSC (WebKit) crashes when viem does `"data" in err` and err is a primitive.
// This wrapper ensures every rejection is a proper Error object.
function toError(e: unknown): Error {
  if (e instanceof Error) return e;
  return new Error(typeof e === "string" ? e : String(e));
}

async function signTransaction(
  transaction: TransactionSerializable,
  options?: { serializer?: SerializeTransactionFn<TransactionSerializable> },
): Promise<Hex> {
  const serializer = options?.serializer ?? serializeTransaction;
  const unsignedTxHex = serializer(transaction) as Hex;
  try {
    const sigHex = await invoke<string>("sign_local_wallet_transaction", { unsignedTxHex });
    return serializer(transaction, parseLocalWalletSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

function unsupported(method: string) {
  return async () => {
    throw new Error(`Local Wallet: ${method} is not supported by this connector.`);
  };
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

    const request = async ({ method, params }: { method: string; params?: readonly unknown[] }) => {
      try {
        if (method === "eth_chainId") return numberToHex(chain.id);
        if (method === "eth_accounts") return cachedAddress ? [cachedAddress] : [];

        if (method === "eth_sendTransaction") {
          if (!cachedAddress) throw new Error("Local wallet not connected.");
          if (!transport) throw new Error(`No RPC transport configured for chain ${chain.id}.`);

          const account = toAccount({
            address: cachedAddress,
            signMessage: unsupported("personal_sign"),
            signTypedData: unsupported("eth_signTypedData_v4"),
            signTransaction,
          });
          const client = createWalletClient({ account, chain, transport });
          const [tx] = (params ?? [{}]) as [Parameters<typeof client.sendTransaction>[0]];
          return await client.sendTransaction(tx);
        }

        // personal_sign (EIP-191) — usado pelo consentimento de
        // createIdentity e pela derivação da vault key. params =
        // [messageHex, address]; viem já normaliza qualquer `message`
        // (string UTF-8 ou `{ raw }`) pra hex antes de chamar `request`.
        if (method === "personal_sign") {
          if (!cachedAddress) throw new Error("Local wallet not connected.");
          const [messageHex] = (params ?? []) as [Hex];
          return await signPersonalMessage(messageHex);
        }

        // Encaminha eth_estimateGas, eth_getTransactionCount, eth_call, etc.
        // com fallback entre RPCs — mesmo padrão do `fallback()` do wagmi
        // em wagmi.ts e do restante dos conectores (ledger.ts/trezor.ts).
        const rpcUrls = chain.rpcUrls.default.http;
        let lastError: Error | null = null;
        for (const url of rpcUrls) {
          try {
            const response = await fetch(url, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params: params ?? [] }),
            });
            const json = (await response.json()) as { result?: unknown; error?: { message: string; code: number; data?: unknown } };
            if (json.error) {
              const err = new Error(json.error.message) as Error & { code?: number; data?: unknown };
              err.code = json.error.code;
              err.data = json.error.data;
              throw err;
            }
            return json.result;
          } catch (e) {
            lastError = toError(e);
            continue;
          }
        }
        throw lastError ?? new Error(`Local Wallet: all RPC URLs failed for chain ${chain.id}.`);
      } catch (e) {
        // Garante que o erro é sempre um objeto — JSC (WebKit) quebra se
        // viem fizer `"data" in err` com um primitivo (string do invoke Tauri).
        throw toError(e);
      }
    };

    return custom({ request })({ retryCount: 0 });
  },
}));

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

// Exportado separado do connector porque `createConnector` devolve a
// função-fábrica tipada genericamente — ela não expõe `.id` em tempo de
// tipagem antes de ser resolvida pela wagmi (ver uso em ConnectWallet.tsx).
export const TREZOR_CONNECTOR_ID = "trezor";

let cachedAddress: Hex | null = null;
let cachedAccountIndex: number = 0;

export function setTrezorAccountIndex(index: number) {
  cachedAccountIndex = index;
}

/// Assinatura combinada que o lado Rust devolve: "0x" + r (32 bytes) + s
/// (32 bytes) + v (1 byte, convenção 27/28) — mesmo formato do conector da
/// Ledger (o Rust já reverte o quirk de codificação EIP-155 da trezor-client
/// antes de devolver, ver trezor.rs::format_tx_signature). Aqui é convertida
/// pro formato que o `serializeTransaction` da viem espera (`yParity`).
function parseTrezorSignature(sigHex: string) {
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
    return serializer(transaction, parseTrezorSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

function unsupported(method: string) {
  return async () => {
    throw new Error(`Trezor: ${method} is not supported by this connector.`);
  };
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

    const request = async ({ method, params }: { method: string; params?: readonly unknown[] }) => {
      try {
        if (method === "eth_chainId") return numberToHex(chain.id);
        if (method === "eth_accounts") return cachedAddress ? [cachedAddress] : [];

        if (method === "eth_sendTransaction") {
          if (!cachedAddress) throw new Error("Trezor not connected.");
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
        // createIdentity, via wagmi's useSignMessage(). params =
        // [messageHex, address]; viem já normaliza qualquer `message`
        // (string UTF-8 ou `{ raw }`) pra hex antes de chamar `request`.
        if (method === "personal_sign") {
          if (!cachedAddress) throw new Error("Trezor not connected.");
          const [messageHex] = (params ?? []) as [Hex];
          return await signPersonalMessage(messageHex);
        }

        // Encaminha eth_estimateGas, eth_getTransactionCount, eth_call, etc.
        // com fallback entre RPCs — mesmo padrão do conector da Ledger.
        const rpcUrls = chain.rpcUrls.default.http;
        let lastError: Error | null = null;
        for (const url of rpcUrls) {
          try {
            const response = await fetch(url, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params: params ?? [] }),
            });
            const json = await response.json() as { result?: unknown; error?: { message: string; code: number; data?: unknown } };
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
        throw lastError ?? new Error(`Trezor: all RPC URLs failed for chain ${chain.id}.`);
      } catch (e) {
        throw toError(e);
      }
    };

    return custom({ request })({ retryCount: 0 });
  },
}));

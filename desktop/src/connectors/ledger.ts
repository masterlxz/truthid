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
export const LEDGER_CONNECTOR_ID = "ledger";

let cachedAddress: Hex | null = null;
let cachedAccountIndex: number = 0;

export function setLedgerAccountIndex(index: number) {
  cachedAccountIndex = index;
}

/// Assinatura combinada que o lado Rust devolve: "0x" + r (32 bytes) + s
/// (32 bytes) + v (1 byte, convenção 27/28) — mesmo formato de
/// `sign_challenge` (ver desktop/src-tauri/src/lib.rs). Aqui é convertida
/// pro formato que o `serializeTransaction` da viem espera (`yParity`).
function parseLedgerSignature(sigHex: string) {
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
    const sigHex = await invoke<string>("sign_ledger_transaction", {
      unsignedTxHex,
      accountIndex: cachedAccountIndex,
    });
    return serializer(transaction, parseLedgerSignature(sigHex)) as Hex;
  } catch (e) {
    throw toError(e);
  }
}

function unsupported(method: string) {
  return async () => {
    throw new Error(`Ledger: ${method} is not supported by this connector.`);
  };
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

    const request = async ({ method, params }: { method: string; params?: readonly unknown[] }) => {
      try {
        if (method === "eth_chainId") return numberToHex(chain.id);
        if (method === "eth_accounts") return cachedAddress ? [cachedAddress] : [];

        if (method === "eth_sendTransaction") {
          if (!cachedAddress) throw new Error("Ledger not connected.");
          if (!transport) throw new Error(`No RPC transport configured for chain ${chain.id}.`);

          // `signMessage`/`signTypedData` aqui não têm relação com o método
          // "personal_sign" tratado abaixo — este `toAccount` é usado só
          // internamente pra montar o `walletClient.sendTransaction`, que
          // nunca invoca assinatura de mensagem.
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
        // createIdentity (débito #17), via wagmi's useSignMessage(). params
        // = [messageHex, address]; viem já normaliza qualquer `message`
        // (string UTF-8 ou `{ raw }`) pra hex antes de chamar `request`.
        if (method === "personal_sign") {
          if (!cachedAddress) throw new Error("Ledger not connected.");
          const [messageHex] = (params ?? []) as [Hex];
          return await signPersonalMessage(messageHex);
        }

        // Encaminha eth_estimateGas, eth_getTransactionCount, eth_call, etc.
        // diretamente ao RPC público via fetch — evita incompatibilidade de
        // tipos entre custom provider e createPublicClient no JSC (WebKit).
        const rpcUrls = chain.rpcUrls.default.http;
        const url = rpcUrls[0];
        if (!url) throw new Error(`Ledger: no RPC URL for chain ${chain.id}.`);

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
        // Garante que o erro é sempre um objeto — JSC (WebKit) quebra se
        // viem fizer `"data" in err` com um primitivo (string do invoke Tauri).
        throw toError(e);
      }
    };

    return custom({ request })({ retryCount: 0 });
  },
}));

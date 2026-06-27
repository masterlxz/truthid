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

async function signTransaction(
  transaction: TransactionSerializable,
  options?: { serializer?: SerializeTransactionFn<TransactionSerializable> },
): Promise<Hex> {
  const serializer = options?.serializer ?? serializeTransaction;
  const unsignedTxHex = serializer(transaction) as Hex;
  const sigHex = await invoke<string>("sign_ledger_transaction", { unsignedTxHex });
  return serializer(transaction, parseLedgerSignature(sigHex)) as Hex;
}

function unsupported(method: string) {
  return async () => {
    throw new Error(`Ledger: ${method} não é suportado por este conector.`);
  };
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
    const found = await invoke<string>("get_ledger_address");
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
    if (!cachedAddress) throw new Error("Ledger não conectada.");
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
      if (method === "eth_chainId") return numberToHex(chain.id);
      if (method === "eth_accounts") return cachedAddress ? [cachedAddress] : [];

      if (method === "eth_sendTransaction") {
        if (!cachedAddress) throw new Error("Ledger não conectada.");
        if (!transport) throw new Error(`Sem transporte RPC configurado para a chain ${chain.id}.`);

        const account = toAccount({
          address: cachedAddress,
          signMessage: unsupported("personal_sign"),
          signTypedData: unsupported("eth_signTypedData_v4"),
          signTransaction,
        });
        const client = createWalletClient({ account, chain, transport });
        const [tx] = (params ?? [{}]) as [Parameters<typeof client.sendTransaction>[0]];
        return client.sendTransaction(tx);
      }

      throw new Error(`Ledger: método ${method} não é suportado por este conector.`);
    };

    return custom({ request })({ retryCount: 0 });
  },
}));

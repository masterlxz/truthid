import { createWalletClient, numberToHex, type Chain, type Hex, type Transport } from "viem";
import { toAccount, type CustomSource } from "viem/accounts";

// Lógica compartilhada pelos 3 conectores EVM sem WalletConnect
// (ledger.ts/trezor.ts/localWallet.ts) — todos assinam via um comando Tauri
// (HID/USB pra Ledger/Trezor, cifra local pra localWallet) mas encaminham o
// resto do provider EIP-1193 (chainId/accounts/sendTransaction/personal_sign
// e o fallback de RPC pra tudo mais) da mesma forma. Extraído depois do
// `/code-review` (P84 #10, Sessão 226) apontar ~90 linhas quase idênticas
// nos 3 arquivos.

// Tauri's invoke() rejects with a plain string when Rust returns Err(...).
// JSC (WebKit) crashes when viem does `"data" in err` and err is a primitive.
// This wrapper ensures every rejection is a proper Error object.
export function toError(e: unknown): Error {
  if (e instanceof Error) return e;
  return new Error(typeof e === "string" ? e : String(e));
}

/// Assinatura combinada que o lado Rust devolve pros 3 conectores: "0x" + r
/// (32 bytes) + s (32 bytes) + v (1 byte, convenção 27/28). Convertida pro
/// formato que `serializeTransaction` da viem espera (`yParity`).
export function parseRsvSignature(sigHex: string): { r: Hex; s: Hex; yParity: number } {
  const r = `0x${sigHex.slice(2, 66)}` as Hex;
  const s = `0x${sigHex.slice(66, 130)}` as Hex;
  const v = Number.parseInt(sigHex.slice(130, 132), 16);
  return { r, s, yParity: v - 27 };
}

export function unsupportedMethod(walletLabel: string, method: string) {
  return async () => {
    throw new Error(`${walletLabel}: ${method} is not supported by this connector.`);
  };
}

/// Encaminha um método de RPC genérico (eth_estimateGas,
/// eth_getTransactionCount, eth_call, etc) com fallback entre RPCs — mesmo
/// padrão do `fallback()` do wagmi em wagmi.ts e do `_rpcCall` no mobile
/// (blockchain_service.dart). Sem nada específico de wallet: os 3 conectores
/// chamavam exatamente o mesmo corpo aqui.
export async function rpcFallbackRequest(
  rpcUrls: readonly string[],
  method: string,
  params: readonly unknown[] | undefined,
  allFailedMessage: string,
): Promise<unknown> {
  let lastError: Error | null = null;
  for (const url of rpcUrls) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params: params ?? [] }),
      });
      const json = (await response.json()) as {
        result?: unknown;
        error?: { message: string; code: number; data?: unknown };
      };
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
  throw lastError ?? new Error(allFailedMessage);
}

/// Monta o `request` do provider EIP-1193 devolvido por `getProvider()` —
/// mesmo dispatcher (eth_chainId/eth_accounts/eth_sendTransaction/
/// personal_sign + fallback de RPC pro resto) usado pelos 3 conectores,
/// parametrizado só no que cada um faz de fato diferente: como assina
/// transação/mensagem, e as mensagens de erro específicas da wallet (que
/// diferem em capitalização entre elas, ex. "Local wallet not connected."
/// vs "Ledger not connected." — preservadas ao pé da letra, os testes de
/// cada conector checam essas strings).
export function createEvmProviderRequest(options: {
  chain: Chain;
  transport: Transport | undefined;
  walletLabel: string;
  notConnectedMessage: string;
  getCachedAddress: () => Hex | null;
  signTransaction: CustomSource["signTransaction"];
  signPersonalMessage: (messageHex: Hex) => Promise<Hex>;
}) {
  const { chain, transport, walletLabel, notConnectedMessage, getCachedAddress, signTransaction, signPersonalMessage } =
    options;

  return async ({ method, params }: { method: string; params?: readonly unknown[] }) => {
    try {
      if (method === "eth_chainId") return numberToHex(chain.id);
      if (method === "eth_accounts") {
        const cachedAddress = getCachedAddress();
        return cachedAddress ? [cachedAddress] : [];
      }

      if (method === "eth_sendTransaction") {
        const cachedAddress = getCachedAddress();
        if (!cachedAddress) throw new Error(notConnectedMessage);
        if (!transport) throw new Error(`No RPC transport configured for chain ${chain.id}.`);

        const account = toAccount({
          address: cachedAddress,
          signMessage: unsupportedMethod(walletLabel, "personal_sign"),
          signTypedData: unsupportedMethod(walletLabel, "eth_signTypedData_v4"),
          signTransaction,
        });
        const client = createWalletClient({ account, chain, transport });
        const [tx] = (params ?? [{}]) as [Parameters<typeof client.sendTransaction>[0]];
        return await client.sendTransaction(tx);
      }

      // personal_sign (EIP-191) — usado pelo consentimento de createIdentity
      // (e, pra wallet local, também pela derivação da vault key). params =
      // [messageHex, address]; viem já normaliza qualquer `message` (string
      // UTF-8 ou `{ raw }`) pra hex antes de chamar `request`.
      if (method === "personal_sign") {
        const cachedAddress = getCachedAddress();
        if (!cachedAddress) throw new Error(notConnectedMessage);
        const [messageHex] = (params ?? []) as [Hex];
        return await signPersonalMessage(messageHex);
      }

      return await rpcFallbackRequest(
        chain.rpcUrls.default.http,
        method,
        params,
        `${walletLabel}: all RPC URLs failed for chain ${chain.id}.`,
      );
    } catch (e) {
      // Garante que o erro é sempre um objeto — JSC (WebKit) quebra se viem
      // fizer `"data" in err` com um primitivo (string do invoke Tauri).
      throw toError(e);
    }
  };
}

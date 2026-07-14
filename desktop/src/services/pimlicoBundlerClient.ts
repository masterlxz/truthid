import type { Address, Hex } from "viem";

import { ENTRY_POINT_V07, type UserOperationV07 } from "../utils/userOperation";

// Monta a URL do bundler Pimlico a partir da chave de API e da rede
// ("base", "base-sepolia", ...) — mirror de `pimlicoBundlerUrl` em
// `mobile/lib/services/pimlico_bundler_client.dart`.
export function pimlicoBundlerUrl({
  apiKey,
  network,
}: {
  apiKey: string;
  network: string;
}): string {
  return `https://api.pimlico.io/v2/${network}/rpc?apikey=${apiKey}`;
}

// Transporte JSON-RPC genérico via `fetch` — mirror de `JsonRpcTransport`.
async function rpcCall(url: string, method: string, params: unknown[]): Promise<unknown> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", method, params, id: 1 }),
  });
  const json = (await response.json()) as { result?: unknown; error?: unknown };

  if (json.error) {
    throw new Error(`RPC error: ${JSON.stringify(json.error)}`);
  }

  return json.result;
}

function hexToBigInt(hex: string): bigint {
  return BigInt(hex);
}

// Serializa uma UserOperationV07 para o formato "não empacotado" que o
// bundler espera via JSON-RPC — mirror de `_userOperationToRpc`. `factory`/
// `factoryData` e os 4 campos de paymaster só entram se de fato presentes,
// espelhando `formatUserOperationRequest` do viem/account-abstraction.
function userOperationToRpc(op: UserOperationV07): Record<string, unknown> {
  const json: Record<string, unknown> = {
    sender: op.sender,
    nonce: `0x${op.nonce.toString(16)}`,
    callData: op.callData,
    callGasLimit: `0x${op.callGasLimit.toString(16)}`,
    verificationGasLimit: `0x${op.verificationGasLimit.toString(16)}`,
    preVerificationGas: `0x${op.preVerificationGas.toString(16)}`,
    maxFeePerGas: `0x${op.maxFeePerGas.toString(16)}`,
    maxPriorityFeePerGas: `0x${op.maxPriorityFeePerGas.toString(16)}`,
    signature: op.signature,
  };

  if (op.factory) {
    json.factory = op.factory;
    json.factoryData = op.factoryData ?? "0x";
  }

  if (op.paymaster) {
    json.paymaster = op.paymaster;
    json.paymasterVerificationGasLimit = `0x${(op.paymasterVerificationGasLimit ?? 0n).toString(16)}`;
    json.paymasterPostOpGasLimit = `0x${(op.paymasterPostOpGasLimit ?? 0n).toString(16)}`;
    json.paymasterData = op.paymasterData ?? "0x";
  }

  return json;
}

// Estimativa de gas devolvida por eth_estimateUserOperationGas — mirror de
// `UserOperationGasEstimate`.
export interface UserOperationGasEstimate {
  callGasLimit: bigint;
  verificationGasLimit: bigint;
  preVerificationGas: bigint;
  paymasterVerificationGasLimit?: bigint;
  paymasterPostOpGasLimit?: bigint;
}

function gasEstimateFromRpc(json: Record<string, unknown>): UserOperationGasEstimate {
  return {
    callGasLimit: hexToBigInt(json.callGasLimit as string),
    verificationGasLimit: hexToBigInt(json.verificationGasLimit as string),
    preVerificationGas: hexToBigInt(json.preVerificationGas as string),
    paymasterVerificationGasLimit:
      json.paymasterVerificationGasLimit != null
        ? hexToBigInt(json.paymasterVerificationGasLimit as string)
        : undefined,
    paymasterPostOpGasLimit:
      json.paymasterPostOpGasLimit != null
        ? hexToBigInt(json.paymasterPostOpGasLimit as string)
        : undefined,
  };
}

// Faixa de preço de gas sugerida pelo bundler — método específico da
// Pimlico (pimlico_getUserOperationGasPrice, não é ERC-4337 padrão). O
// bundler devolve 3 tiers (slow/standard/fast); usamos sempre "fast", mesma
// escolha do Mobile, pra minimizar o risco de a UserOp ficar presa no
// mempool por taxa baixa.
export interface UserOperationGasPrice {
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
}

function gasPriceFromRpc(json: Record<string, unknown>): UserOperationGasPrice {
  const fast = json.fast as Record<string, unknown>;
  return {
    maxFeePerGas: hexToBigInt(fast.maxFeePerGas as string),
    maxPriorityFeePerGas: hexToBigInt(fast.maxPriorityFeePerGas as string),
  };
}

// Recibo devolvido por eth_getUserOperationReceipt — só os campos
// consumidos hoje, mirror de `UserOperationReceipt`.
export interface UserOperationReceipt {
  userOpHash: Hex;
  success: boolean;
  actualGasCost: bigint;
  actualGasUsed: bigint;
  transactionHash: Hex;
}

function receiptFromRpc(json: Record<string, unknown>): UserOperationReceipt {
  const receipt = json.receipt as Record<string, unknown>;
  return {
    userOpHash: json.userOpHash as Hex,
    success: json.success as boolean,
    actualGasCost: hexToBigInt(json.actualGasCost as string),
    actualGasUsed: hexToBigInt(json.actualGasUsed as string),
    transactionHash: receipt.transactionHash as Hex,
  };
}

// Cliente JSON-RPC do bundler Pimlico (ERC-4337 v0.7) — mirror de
// `PimlicoBundlerClient` (mobile/lib/services/pimlico_bundler_client.dart).
export class PimlicoBundlerClient {
  private readonly bundlerUrl: string;
  private readonly entryPoint: Address;

  constructor({ bundlerUrl, entryPoint }: { bundlerUrl: string; entryPoint?: Address }) {
    this.bundlerUrl = bundlerUrl;
    this.entryPoint = entryPoint ?? ENTRY_POINT_V07;
  }

  async estimateUserOperationGas(op: UserOperationV07): Promise<UserOperationGasEstimate> {
    const result = await rpcCall(this.bundlerUrl, "eth_estimateUserOperationGas", [
      userOperationToRpc(op),
      this.entryPoint,
    ]);
    return gasEstimateFromRpc(result as Record<string, unknown>);
  }

  async getUserOperationGasPrice(): Promise<UserOperationGasPrice> {
    const result = await rpcCall(this.bundlerUrl, "pimlico_getUserOperationGasPrice", []);
    return gasPriceFromRpc(result as Record<string, unknown>);
  }

  async sendUserOperation(op: UserOperationV07): Promise<Hex> {
    const result = await rpcCall(this.bundlerUrl, "eth_sendUserOperation", [
      userOperationToRpc(op),
      this.entryPoint,
    ]);
    return result as Hex;
  }

  // Enquanto a UserOperation ainda não foi minerada, o bundler devolve
  // `result: null` (sem `error`) — por isso o retorno é opcional.
  async getUserOperationReceipt(userOpHash: Hex): Promise<UserOperationReceipt | null> {
    const result = await rpcCall(this.bundlerUrl, "eth_getUserOperationReceipt", [userOpHash]);
    if (result == null) return null;
    return receiptFromRpc(result as Record<string, unknown>);
  }
}

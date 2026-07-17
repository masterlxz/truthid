import { invoke } from "@tauri-apps/api/core";
import type { Address, Hex } from "viem";
import { encodeFunctionData } from "viem";
import { readContract } from "wagmi/actions";

import { TRUTHID_ACCOUNT_ABI } from "../config/contracts";
import { config } from "../config/wagmi";
import {
  ENTRY_POINT_V07,
  computeUserOperationHash,
  type UserOperationV07,
} from "../utils/userOperation";
import { PimlicoBundlerClient, pimlicoBundlerUrl } from "./pimlicoBundlerClient";

const ENTRY_POINT_ABI = [
  {
    type: "function",
    name: "getNonce",
    inputs: [
      { name: "sender", type: "address" },
      { name: "key", type: "uint192" },
    ],
    outputs: [{ name: "nonce", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

// Base Mainnet — mesmo valor de `mobile/lib/services/blockchain_service.dart`
// (`chainId`) e da chain `base` já configurada em `desktop/src/config/wagmi.ts`.
const CHAIN_ID = 8453n;

// Polling do recibo: 30 tentativas de 2s (~60s) — mesmo padrão de
// `SessionCreator._waitForReceipt` no Mobile.
const RECEIPT_POLL_INTERVAL_MS = 2000;
const RECEIPT_POLL_MAX_ATTEMPTS = 30;

const ZERO_SIGNATURE_65_BYTES: Hex = `0x${"00".repeat(65)}`;

export interface ExecuteViaUserOpResult {
  userOpHash: Hex;
  transactionHash: Hex | null;
}

/**
 * Monta, assina (com a device key, via comando Tauri `sign_user_op_hash` —
 * sem Ledger) e envia uma UserOperation que chama `execute(dest, value,
 * callData)` na smart account do usuário. Mirror de
 * `SessionCreator._executeViaUserOp`
 * (mobile/lib/services/session_creator.dart) — mesmo núcleo que o Mobile já
 * usa em produção pra createSession/revokeSession/withdraw/updateVault.
 *
 * A smart account paga o próprio gas (sem paymaster — ver PROJECT_STATE.md,
 * Sessão 52); precisa ter ETH depositado. `dest` genérico de propósito: já
 * pronto pra, numa fatia futura, apontar pra qualquer contrato de terceiro,
 * não só o VaultRegistry.
 */
export async function executeViaUserOp({
  smartAccountAddress,
  dest,
  value,
  callData,
  bundlerApiKey,
  bundlerNetwork,
}: {
  smartAccountAddress: Address;
  dest: Address;
  value: bigint;
  callData: Hex;
  bundlerApiKey: string;
  bundlerNetwork: string;
}): Promise<ExecuteViaUserOpResult> {
  const bundlerClient = new PimlicoBundlerClient({
    bundlerUrl: pimlicoBundlerUrl({ apiKey: bundlerApiKey, network: bundlerNetwork }),
  });

  const executeCallData = encodeFunctionData({
    abi: TRUTHID_ACCOUNT_ABI,
    functionName: "execute",
    args: [dest, value, callData],
  });

  const nonce = await readContract(config, {
    address: ENTRY_POINT_V07,
    abi: ENTRY_POINT_ABI,
    functionName: "getNonce",
    args: [smartAccountAddress, 0n],
  });

  const gasPrice = await bundlerClient.getUserOperationGasPrice();

  let userOp: UserOperationV07 = {
    sender: smartAccountAddress,
    nonce,
    callData: executeCallData,
    callGasLimit: 0n,
    verificationGasLimit: 0n,
    preVerificationGas: 0n,
    maxFeePerGas: gasPrice.maxFeePerGas,
    maxPriorityFeePerGas: gasPrice.maxPriorityFeePerGas,
    // substituído abaixo antes da estimativa, nunca enviado assinado assim.
    signature: ZERO_SIGNATURE_65_BYTES,
  };

  // A estimativa de gas precisa de uma assinatura real da device key, não de
  // um placeholder zerado: `TruthIDAccount._validateSignature` rejeita v=0
  // antes até de chamar ecrecover, então o custo de
  // `authorizedDevices`/`_isDeviceCallAllowed` (que só roda quando o signer
  // recuperado bate com um device autorizado) nunca entraria na simulação —
  // foi a causa raiz do AA26 (verificationGasLimit subestimado) achado na
  // Sessão 114 com hardware real. O hash aqui é só da UserOp com gas
  // zerado; é reassinada mais abaixo com os valores reais antes do envio.
  const dummyUserOpHash = computeUserOperationHash({
    userOperation: userOp,
    entryPoint: ENTRY_POINT_V07,
    chainId: CHAIN_ID,
  });
  userOp = {
    ...userOp,
    signature: await invoke<Hex>("sign_user_op_hash", { hash: dummyUserOpHash }),
  };

  const estimate = await bundlerClient.estimateUserOperationGas(userOp);
  userOp = {
    ...userOp,
    callGasLimit: estimate.callGasLimit,
    verificationGasLimit: estimate.verificationGasLimit,
    preVerificationGas: estimate.preVerificationGas,
  };

  const userOpHash = computeUserOperationHash({
    userOperation: userOp,
    entryPoint: ENTRY_POINT_V07,
    chainId: CHAIN_ID,
  });
  const signature = await invoke<Hex>("sign_user_op_hash", { hash: userOpHash });
  const signedOp: UserOperationV07 = { ...userOp, signature };

  const sentUserOpHash = await bundlerClient.sendUserOperation(signedOp);
  const receipt = await waitForReceipt(bundlerClient, sentUserOpHash);

  return {
    userOpHash: sentUserOpHash,
    transactionHash: receipt?.transactionHash ?? null,
  };
}

async function waitForReceipt(
  bundlerClient: PimlicoBundlerClient,
  userOpHash: Hex,
): Promise<{ transactionHash: Hex } | null> {
  for (let attempt = 0; attempt < RECEIPT_POLL_MAX_ATTEMPTS; attempt++) {
    const receipt = await bundlerClient.getUserOperationReceipt(userOpHash);
    if (receipt) return receipt;
    await new Promise((resolve) => setTimeout(resolve, RECEIPT_POLL_INTERVAL_MS));
  }
  return null;
}

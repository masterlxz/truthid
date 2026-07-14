import { type Address, type Hex, concat, keccak256, numberToHex, pad } from "viem";

// Endereço padrão do EntryPoint v0.7 (eth-infinitism) — mesmo em todas as
// chains. Idêntico ao valor já usado no Mobile
// (mobile/lib/utils/user_operation.dart) e em desktop/src/config/truthidAccount.ts
// (ENTRY_POINT_V07) — mantido aqui também porque este módulo precisa dele
// como default, sem depender de importar config do resto do app.
export const ENTRY_POINT_V07: Address = "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

/**
 * User Operation ERC-4337 v0.7, na forma "não empacotada" usada pelos
 * métodos JSON-RPC do bundler (eth_sendUserOperation, eth_estimateUserOperationGas).
 * Mirror de `UserOperationV07` em `mobile/lib/utils/user_operation.dart`.
 */
export interface UserOperationV07 {
  sender: Address;
  nonce: bigint;
  factory?: Address;
  factoryData?: Hex;
  callData: Hex;
  callGasLimit: bigint;
  verificationGasLimit: bigint;
  preVerificationGas: bigint;
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
  paymaster?: Address;
  paymasterVerificationGasLimit?: bigint;
  paymasterPostOpGasLimit?: bigint;
  paymasterData?: Hex;
  signature: Hex;
}

/**
 * Forma "empacotada" da User Operation — a que o EntryPoint/TruthIDAccount
 * realmente decodifica on-chain (struct PackedUserOperation do eth-infinitism).
 * `accountGasLimits` e `gasFees` são cada um 32 bytes (dois uint128 concatenados).
 */
export interface PackedUserOperation {
  sender: Address;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: bigint;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
}

function addressWord(address: Address): Hex {
  return pad(address, { size: 32 });
}

function uintWord(value: bigint): Hex {
  return numberToHex(value, { size: 32 });
}

function packUint128Pair(hi: bigint, lo: bigint): Hex {
  return concat([numberToHex(hi, { size: 16 }), numberToHex(lo, { size: 16 })]);
}

function buildInitCode(op: UserOperationV07): Hex {
  if (!op.factory) return "0x";
  return concat([op.factory, op.factoryData ?? "0x"]);
}

function buildPaymasterAndData(op: UserOperationV07): Hex {
  if (!op.paymaster) return "0x";
  return concat([
    op.paymaster,
    numberToHex(op.paymasterVerificationGasLimit ?? 0n, { size: 16 }),
    numberToHex(op.paymasterPostOpGasLimit ?? 0n, { size: 16 }),
    op.paymasterData ?? "0x",
  ]);
}

export function toPackedUserOperation(op: UserOperationV07): PackedUserOperation {
  return {
    sender: op.sender,
    nonce: op.nonce,
    initCode: buildInitCode(op),
    callData: op.callData,
    accountGasLimits: packUint128Pair(op.verificationGasLimit, op.callGasLimit),
    preVerificationGas: op.preVerificationGas,
    gasFees: packUint128Pair(op.maxPriorityFeePerGas, op.maxFeePerGas),
    paymasterAndData: buildPaymasterAndData(op),
    signature: op.signature,
  };
}

/**
 * Espelha bit a bit `EntryPoint.getUserOpHash` / `UserOperationLib.hash` (v0.7)
 * — mesma fórmula implementada em `mobile/lib/utils/user_operation.dart`:
 *
 *   innerHash = keccak256(abi.encode(
 *     sender, nonce, keccak256(initCode), keccak256(callData),
 *     accountGasLimits, preVerificationGas, gasFees, keccak256(paymasterAndData)
 *   ))
 *   userOpHash = keccak256(abi.encode(innerHash, entryPoint, chainId))
 *
 * Todos os campos do `abi.encode` acima são de tamanho estático (address,
 * uint256, bytes32), então a codificação é só a concatenação de palavras de
 * 32 bytes, sem cabeçalhos de offset — dispensa `encodeAbiParameters`.
 */
export function computeUserOperationHash({
  userOperation,
  entryPoint,
  chainId,
}: {
  userOperation: UserOperationV07;
  entryPoint: Address;
  chainId: bigint;
}): Hex {
  const packed = toPackedUserOperation(userOperation);

  const innerEncoded = concat([
    addressWord(packed.sender),
    uintWord(packed.nonce),
    keccak256(packed.initCode),
    keccak256(packed.callData),
    packed.accountGasLimits,
    uintWord(packed.preVerificationGas),
    packed.gasFees,
    keccak256(packed.paymasterAndData),
  ]);
  const innerHash = keccak256(innerEncoded);

  const outerEncoded = concat([innerHash, addressWord(entryPoint), uintWord(chainId)]);
  return keccak256(outerEncoded);
}

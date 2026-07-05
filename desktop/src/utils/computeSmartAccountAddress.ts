import {
  type Address,
  type PublicClient,
  keccak256,
  encodeAbiParameters,
  encodePacked,
  concat,
  slice,
  getAddress,
} from "viem";
import {
  TRUTHID_ACCOUNT_CREATION_CODE,
} from "../config/truthidAccount";

const TRUTHID_ACCOUNT_FACTORY_ABI = [
  { type: "function", name: "entryPoint", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "deviceRegistry", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "identityRegistry", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "recoveryManager", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
] as const;

interface ComputeAddressFromFactory {
  ledgerAddress: Address;
  factoryAddress: Address;
  publicClient: PublicClient;
  index?: bigint;
}

interface ComputeAddressExplicit extends Record<string, unknown> {
  ledgerAddress: Address;
  factoryAddress: Address;
  entryPoint: Address;
  deviceRegistry: Address;
  identityRegistry: Address;
  recoveryManager: Address;
  index?: bigint;
}

type ComputeSmartAccountParams = ComputeAddressFromFactory | ComputeAddressExplicit;

function isExplicitParams(params: ComputeSmartAccountParams): params is ComputeAddressExplicit {
  return "entryPoint" in params;
}

/**
 * Computes the deterministic CREATE2 address of a TruthIDAccount before it is
 * deployed — mirroring `TruthIDAccountFactory.getAddress()` on-chain.
 *
 * Two modes:
 * 1. **From factory** — pass `publicClient` and the function reads the 4
 *    factory immutables on-chain (free `eth_call`, no gas).
 * 2. **Explicit** — pass `entryPoint`, `deviceRegistry`, `identityRegistry`,
 *    `recoveryManager` directly (useful pre-deploy or offline).
 *
 * Formula (same as Solidity):
 *   salt = keccak256(abi.encodePacked(ledgerAddress, index))
 *   initCode = creationCode || abi.encode(entryPoint, deviceRegistry, identityRegistry, recoveryManager, ledgerAddress)
 *   initCodeHash = keccak256(initCode)
 *   address = last 20 bytes of keccak256(0xFF || factoryAddress || salt || initCodeHash)
 *
 * `index` defaults to 0 (primary account). Use index > 0 for account resets
 * or additional accounts per Ledger (débito #25).
 */
export async function computeSmartAccountAddress(
  params: ComputeSmartAccountParams,
): Promise<Address> {
  let entryPoint: Address;
  let deviceRegistry: Address;
  let identityRegistry: Address;
  let recoveryManager: Address;

  if (isExplicitParams(params)) {
    entryPoint = params.entryPoint;
    deviceRegistry = params.deviceRegistry;
    identityRegistry = params.identityRegistry;
    recoveryManager = params.recoveryManager;
  } else {
    const results = await params.publicClient.multicall({
      contracts: [
        { address: params.factoryAddress, abi: TRUTHID_ACCOUNT_FACTORY_ABI, functionName: "entryPoint" },
        { address: params.factoryAddress, abi: TRUTHID_ACCOUNT_FACTORY_ABI, functionName: "deviceRegistry" },
        { address: params.factoryAddress, abi: TRUTHID_ACCOUNT_FACTORY_ABI, functionName: "identityRegistry" },
        { address: params.factoryAddress, abi: TRUTHID_ACCOUNT_FACTORY_ABI, functionName: "recoveryManager" },
      ],
    });

    entryPoint = results[0].result as Address;
    deviceRegistry = results[1].result as Address;
    identityRegistry = results[2].result as Address;
    recoveryManager = results[3].result as Address;
  }

  return computeAddress(params.ledgerAddress, params.factoryAddress, {
    entryPoint,
    deviceRegistry,
    identityRegistry,
    recoveryManager,
  }, params.index ?? 0n);
}

interface FactoryImmutables {
  entryPoint: Address;
  deviceRegistry: Address;
  identityRegistry: Address;
  recoveryManager: Address;
}

export function computeSmartAccountAddressSync(
  ledgerAddress: Address,
  factoryAddress: Address,
  immutables: FactoryImmutables,
  index: bigint = 0n,
): Address {
  return computeAddress(ledgerAddress, factoryAddress, immutables, index);
}

function computeAddress(
  ledgerAddress: Address,
  factoryAddress: Address,
  immutables: FactoryImmutables,
  index: bigint,
): Address {
  // Precisa ser encodePacked, não encodeAbiParameters — o contrato usa
  // `abi.encodePacked(owner_, index)` (endereço sem left-pad, 20 bytes), não
  // `abi.encode` (endereço com left-pad, 32 bytes). Usar o encoding errado
  // aqui produz um salt diferente do que a factory calcula on-chain,
  // gerando um `controller` que nunca bate com `factory.getAddress(...)` —
  // acabou de causar um `InvalidConsentSignature` real (Sessão 70).
  const salt = keccak256(
    encodePacked(["address", "uint256"], [ledgerAddress, index]),
  );

  const constructorArgs = encodeAbiParameters(
    [
      { type: "address" },
      { type: "address" },
      { type: "address" },
      { type: "address" },
      { type: "address" },
    ],
    [
      immutables.entryPoint,
      immutables.deviceRegistry,
      immutables.identityRegistry,
      immutables.recoveryManager,
      ledgerAddress,
    ],
  );

  const initCode = concat([TRUTHID_ACCOUNT_CREATION_CODE, constructorArgs]);
  const initCodeHash = keccak256(initCode);

  const create2Input = concat(["0xff", factoryAddress, salt, initCodeHash]);
  const hash = keccak256(create2Input);

  return getAddress(slice(hash, 12));
}
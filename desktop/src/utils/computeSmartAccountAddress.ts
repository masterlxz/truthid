import {
  type Address,
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
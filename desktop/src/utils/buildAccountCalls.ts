import { type Abi, type Address, type Hex, encodeFunctionData } from "viem";

interface AccountCall {
  address: Address;
  abi: Abi;
  functionName: string;
  args: readonly unknown[];
}

/**
 * Encodes a list of calls into the `dest`/`value`/`func` arrays that
 * `TruthIDAccount.executeBatch` expects. Each call is ABI-encoded on its own
 * (viem's `encodeFunctionData`), so calls can target different contracts
 * (e.g. `DeviceRegistry` and the smart account itself) in the same batch.
 * `value` is always `0n` here — nothing in this app sends ETH alongside a
 * device-sync call.
 */
export function buildAccountCalls(calls: AccountCall[]): {
  dest: Address[];
  value: bigint[];
  func: Hex[];
} {
  return {
    dest: calls.map((call) => call.address),
    value: calls.map(() => 0n),
    func: calls.map((call) =>
      encodeFunctionData({
        abi: call.abi,
        functionName: call.functionName,
        args: call.args,
      } as Parameters<typeof encodeFunctionData>[0]),
    ),
  };
}

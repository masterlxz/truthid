import { invoke } from "@tauri-apps/api/core";
import type { Address, Hex } from "viem";
import { encodeFunctionData } from "viem";
import { VAULT_REGISTRY_ADDRESS, VAULT_REGISTRY_ABI } from "../config/contracts";
import { executeViaUserOp } from "./userOpExecutor";
import type { PinResult } from "../types";

interface BundlerConfig {
  api_key: string;
  network: string;
}

/**
 * Extraído de `useVaultPublish.ts::handleEnviarViaDeviceKey` — mesma cadeia
 * (pin local no IPFS via `vault_publish`, depois assina/envia a
 * UserOperation `updateVault` via device key), agora reaproveitável por
 * quem precisa publicar sem estar dentro do hook React (ex:
 * `VaultEditApprovalModal.tsx`, que já chamou `vault_upsert_entry` antes de
 * publicar). Não duplica a lógica — o hook continua sendo a única outra
 * chamadora, sem mudança de comportamento nele.
 */
export async function publishVaultViaDeviceKey(
  smartAccountAddress: Address
): Promise<{ transactionHash: Hex | null }> {
  const result = await invoke<PinResult>("vault_publish");
  if (result.providers_failed.length > 0 && result.providers_ok.length === 0) {
    throw new Error(`Todos os providers falharam: ${result.providers_failed.join(", ")}`);
  }

  const bundlerConfig = await invoke<BundlerConfig>("get_bundler_config");
  if (!bundlerConfig.api_key) {
    throw new Error(
      "Bundler não configurado — grave api_key/network em ~/.truthid/bundler_config.json."
    );
  }

  const callData = encodeFunctionData({
    abi: VAULT_REGISTRY_ABI,
    functionName: "updateVault",
    args: [result.cid, result.content_hash as `0x${string}`],
  });

  const { transactionHash, success } = await executeViaUserOp({
    smartAccountAddress,
    dest: VAULT_REGISTRY_ADDRESS,
    value: 0n,
    callData,
    bundlerApiKey: bundlerConfig.api_key,
    bundlerNetwork: bundlerConfig.network || "base",
  });

  if (!success) throw new Error("Failed to publish vault: on-chain transaction reverted");
  return { transactionHash };
}

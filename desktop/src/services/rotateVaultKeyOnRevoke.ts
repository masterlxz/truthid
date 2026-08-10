import { invoke } from "@tauri-apps/api/core";
import { bytesToHex, type Address, type Hex } from "viem";
import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  VAULT_REGISTRY_ADDRESS,
  VAULT_REGISTRY_ABI,
} from "../config/contracts";
import { buildAccountCalls } from "../utils/buildAccountCalls";
import { base64ToBytes } from "../utils/base64";
import type { PublishResult } from "../types";

/**
 * Roda depois que um `revokeDevice` já confirmou on-chain: gera uma DEK
 * nova, re-cifra o vault local inteiro sob ela (`rotate_vault_key`,
 * Rust), republica (`vault_publish`, mesmo fluxo que o publish manual já
 * usa) e cifra a chave nova via ECIES pra cada device que permanece ativo
 * (`encrypt_vault_key_for_device`, já usado no pareamento — só que agora em
 * loop, não uma vez só).
 *
 * Não assina nada aqui — só devolve `dest`/`value`/`func` prontos pra
 * `writeContract({ functionName: "executeBatch", ... })` contra a smart
 * account, o mesmo caminho Ledger já usado por `handleRevoke` em
 * `ManageDevices.tsx`. Batching os `updateDeviceVaultKey` de todos os
 * devices restantes com o `updateVault` da republicação numa única
 * transação evita um toque de Ledger por device.
 */
export async function buildRotationBatch(
  remainingActiveDevicePubKeys: Address[]
): Promise<{ dest: Address[]; value: bigint[]; func: Hex[] }> {
  await invoke<string>("rotate_vault_key");

  const publishResult = await invoke<PublishResult>("vault_publish");

  const keyUpdateCalls = await Promise.all(
    remainingActiveDevicePubKeys.map(async (pubKey) => {
      const blobB64 = await invoke<string>("encrypt_vault_key_for_device", {
        devicePubkeyHex: pubKey,
      });
      const encryptedVaultKey = bytesToHex(base64ToBytes(blobB64));
      return {
        address: DEVICE_REGISTRY_ADDRESS,
        abi: DEVICE_REGISTRY_ABI,
        functionName: "updateDeviceVaultKey" as const,
        args: [pubKey, encryptedVaultKey] as const,
      };
    })
  );

  const { dest, value, func } = buildAccountCalls([
    ...keyUpdateCalls,
    {
      address: VAULT_REGISTRY_ADDRESS,
      abi: VAULT_REGISTRY_ABI,
      functionName: "updateVault",
      args: [publishResult.cid, publishResult.content_hash as Hex],
    },
  ]);

  return { dest, value, func };
}

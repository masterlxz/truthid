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
 * Um device restante que precisa receber a chave nova na rotação —
 * `pubKey` é o endereço on-chain (identificador em `DeviceRegistry`),
 * `rawPubkeyHex` é a chave pública secp256k1 crua (33/65 bytes) necessária
 * pro ECIES. O contrato só guarda o endereço (ver nota em
 * `DeviceRegistry.sol`), então a chave crua precisa ser recolhida fora da
 * cadeia — reaproveita o mesmo campo "Encryption key" que `PairDevice.tsx`
 * já usa no pareamento inicial (ver `RedistributeVaultKey.tsx`).
 */
export interface RemainingDevice {
  pubKey: Address;
  rawPubkeyHex: string;
}

/**
 * Roda depois que um `revokeDevice` já confirmou on-chain: gera uma DEK
 * nova, cifra ela via ECIES pra CADA device que permanece ativo
 * (`encrypt_key_for_device`), e só se todas essas cifras tiverem sucesso é
 * que commita a chave nova localmente (`rotate_vault_key`) e republica
 * (`vault_publish`).
 *
 * Ordem importa (achado real, P54/Sessão 205): a versão anterior chamava
 * `rotate_vault_key` ANTES de tentar cifrar pros devices restantes — como
 * essa cifra sempre falhava (bug separado: usava o endereço do device em
 * vez da chave pública crua, que o contrato nunca guarda), o Desktop já
 * tinha reescrito o keyring/vault.enc local pra chave nova antes do erro
 * acontecer, ficando dessincronizado do que estava publicado on-chain — sem
 * nenhuma transação ter sido enviada. Agora a chave só é gerada e cifrada
 * em memória (`generate_vault_key_hex`/`encrypt_key_for_device`, nenhum dos
 * dois toca keyring/disco); o commit local (`rotate_vault_key`) só roda
 * depois que a lista inteira de devices restantes já recebeu a cifra certa.
 *
 * Não assina nada aqui — só devolve `dest`/`value`/`func` prontos pra
 * `writeContract({ functionName: "executeBatch", ... })` contra a smart
 * account, o mesmo caminho Ledger já usado por `handleRevoke` em
 * `ManageDevices.tsx`. Batching os `updateDeviceVaultKey` de todos os
 * devices restantes com o `updateVault` da republicação numa única
 * transação evita um toque de Ledger por device.
 */
export async function buildRotationBatch(
  remainingActiveDevices: RemainingDevice[]
): Promise<{ dest: Address[]; value: bigint[]; func: Hex[] }> {
  const newKeyHex = await invoke<string>("generate_vault_key_hex");

  const keyUpdateCalls = await Promise.all(
    remainingActiveDevices.map(async ({ pubKey, rawPubkeyHex }) => {
      const blobB64 = await invoke<string>("encrypt_key_for_device", {
        keyHex: newKeyHex,
        devicePubkeyHex: rawPubkeyHex,
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

  // Só a partir daqui o estado local é mutado — todas as cifras acima já
  // tiveram sucesso.
  await invoke<void>("rotate_vault_key", { newKeyHex });
  const publishResult = await invoke<PublishResult>("vault_publish");

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

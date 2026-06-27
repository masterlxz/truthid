import { createPublicClient, http, recoverMessageAddress } from "viem";
import { baseSepolia, base } from "viem/chains";
import { randomUUID } from "crypto";

import {
  DEVICE_REGISTRY_ADDRESS,
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ADDRESS,
  SESSION_REGISTRY_ABI,
} from "./contracts.js";
import type {
  TruthIDClientConfig,
  AuthChallenge,
  VerifyAuthParams,
  VerifyAuthResult,
  SessionInfo,
  DeviceStatus,
} from "./types.js";

export class TruthIDClient {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private publicClient: any;

  constructor(config: TruthIDClientConfig) {
    const chain = config.network === "base-mainnet" ? base : baseSepolia;
    const rpcUrl =
      config.rpcUrl ??
      (config.network === "base-mainnet"
        ? "https://mainnet.base.org"
        : "https://sepolia.base.org");

    this.publicClient = createPublicClient({
      chain,
      transport: http(rpcUrl),
    });
  }

  // Cria um challenge no formato exato que o mobile espera e assina
  createChallenge(origin: string): AuthChallenge {
    return {
      type: "challenge",
      nonce: randomUUID(),
      issuedAt: Date.now(),
      origin,
    };
  }

  // Verifica a resposta de login que chegou do mobile
  async verifyAuthResponse({
    challenge,
    response,
    ttlMs = 30_000,
  }: VerifyAuthParams): Promise<VerifyAuthResult> {
    // 1. Usuário recusou explicitamente
    if (!response.approved) {
      return { valid: false, reason: "User rejected the login request" };
    }

    // 2. Challenge expirou (proteção anti-replay por tempo)
    if (Date.now() - challenge.issuedAt > ttlMs) {
      return { valid: false, reason: "Challenge expired" };
    }

    // 3. Nonce da resposta precisa bater com o do challenge (proteção anti-replay por conteúdo)
    if (challenge.nonce !== response.nonce) {
      return { valid: false, reason: "Nonce mismatch" };
    }

    // 4. Verificar a assinatura criptográfica
    // O mobile assinou JSON.stringify(challenge) com prefixo Ethereum personal_sign
    // recoverMessageAddress() aplica o mesmo prefixo antes de verificar
    const message = JSON.stringify({
      type: challenge.type,
      nonce: challenge.nonce,
      issuedAt: challenge.issuedAt,
      origin: challenge.origin,
    });

    let signer: string;
    try {
      signer = await recoverMessageAddress({
        message,
        signature: response.signature as `0x${string}`,
      });
    } catch {
      return { valid: false, reason: "Invalid signature format" };
    }

    if (signer.toLowerCase() !== response.deviceAddress.toLowerCase()) {
      return { valid: false, reason: "Signature does not match device address" };
    }

    // 5. Verificar na blockchain se o device ainda está ativo (não foi revogado)
    const isActive = await this.publicClient.readContract({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "isDeviceActive",
      args: [response.deviceAddress as `0x${string}`],
    });

    if (!isActive) {
      return { valid: false, reason: "Device is not active or has been revoked" };
    }

    // 6. Buscar o identityId associado a este device
    const device = await this.publicClient.readContract({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice",
      args: [response.deviceAddress as `0x${string}`],
    });

    return {
      valid: true,
      identityId: device.identityId,
      deviceAddress: response.deviceAddress,
    };
  }

  // Verifica se uma sessão existe e não foi revogada
  async verifySession(hash: string): Promise<SessionInfo> {
    const [session, revoked] = await Promise.all([
      this.publicClient.readContract({
        address: SESSION_REGISTRY_ADDRESS,
        abi: SESSION_REGISTRY_ABI,
        functionName: "getSession",
        args: [hash as `0x${string}`],
      }),
      this.publicClient.readContract({
        address: SESSION_REGISTRY_ADDRESS,
        abi: SESSION_REGISTRY_ABI,
        functionName: "isSessionRevoked",
        args: [hash as `0x${string}`],
      }),
    ]);

    if (!session.exists) {
      return { exists: false, revoked: false };
    }

    return {
      exists: true,
      revoked,
      identityId: session.identityId,
      devicePubKey: session.devicePubKey,
      createdAt: new Date(Number(session.createdAt) * 1000),
    };
  }

  // Verifica o status de um device na blockchain
  async checkDeviceStatus(devicePubKey: string): Promise<DeviceStatus> {
    const device = await this.publicClient.readContract({
      address: DEVICE_REGISTRY_ADDRESS,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "getDevice",
      args: [devicePubKey as `0x${string}`],
    });

    if (!device.exists) {
      return { exists: false, active: false };
    }

    return {
      exists: true,
      active: !device.revoked,
      label: device.label,
      identityId: device.identityId,
      addedAt: new Date(Number(device.addedAt) * 1000),
    };
  }
}

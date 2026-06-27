import { createPublicClient, http, recoverMessageAddress } from "viem";
import { baseSepolia, base } from "viem/chains";
import { randomUUID } from "crypto";

import {
  DEVICE_REGISTRY_ADDRESSES,
  DEVICE_REGISTRY_ABI,
  SESSION_REGISTRY_ADDRESSES,
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
  private deviceRegistryAddress: `0x${string}`;
  private sessionRegistryAddress: `0x${string}`;

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
    this.deviceRegistryAddress = DEVICE_REGISTRY_ADDRESSES[config.network];
    this.sessionRegistryAddress = SESSION_REGISTRY_ADDRESSES[config.network];
  }

  // Creates a challenge in the exact format the mobile expects and signs
  createChallenge(origin: string): AuthChallenge {
    return {
      type: "challenge",
      nonce: randomUUID(),
      issuedAt: Date.now(),
      origin,
    };
  }

  // Verifies the login response received from the mobile
  async verifyAuthResponse({
    challenge,
    response,
    ttlMs = 30_000,
  }: VerifyAuthParams): Promise<VerifyAuthResult> {
    // 1. User explicitly rejected
    if (!response.approved) {
      return { valid: false, reason: "User rejected the login request" };
    }

    // 2. Challenge expired (time-based replay protection)
    if (Date.now() - challenge.issuedAt > ttlMs) {
      return { valid: false, reason: "Challenge expired" };
    }

    // 3. Response nonce must match the challenge nonce (content-based replay protection)
    if (challenge.nonce !== response.nonce) {
      return { valid: false, reason: "Nonce mismatch" };
    }

    // 4. Verify the cryptographic signature
    // The mobile signed JSON.stringify(challenge) with the Ethereum personal_sign prefix
    // recoverMessageAddress() applies the same prefix before verifying
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

    // 5. Check on-chain whether the device is still active (not revoked)
    const isActive = await this.publicClient.readContract({
      address: this.deviceRegistryAddress,
      abi: DEVICE_REGISTRY_ABI,
      functionName: "isDeviceActive",
      args: [response.deviceAddress as `0x${string}`],
    });

    if (!isActive) {
      return { valid: false, reason: "Device is not active or has been revoked" };
    }

    // 6. Fetch the identityId associated with this device
    const device = await this.publicClient.readContract({
      address: this.deviceRegistryAddress,
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

  // Checks whether a session exists and has not been revoked
  async verifySession(hash: string): Promise<SessionInfo> {
    const [session, revoked] = await Promise.all([
      this.publicClient.readContract({
        address: this.sessionRegistryAddress,
        abi: SESSION_REGISTRY_ABI,
        functionName: "getSession",
        args: [hash as `0x${string}`],
      }),
      this.publicClient.readContract({
        address: this.sessionRegistryAddress,
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

  // Checks the status of a device on-chain
  async checkDeviceStatus(devicePubKey: string): Promise<DeviceStatus> {
    const device = await this.publicClient.readContract({
      address: this.deviceRegistryAddress,
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

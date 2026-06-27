export type Network = "base-sepolia" | "base-mainnet";

export interface TruthIDClientConfig {
  network: Network;
  rpcUrl?: string;
}

// Exact format the mobile receives and signs
export interface AuthChallenge {
  type: "challenge";
  nonce: string;
  issuedAt: number; // Unix timestamp in ms
  origin: string;
}

// Response sent by the mobile after the user approves
export interface AuthResponse {
  approved: boolean;
  nonce: string;
  signature: string;     // secp256k1 signature in hex ("0x...")
  deviceAddress: string; // Ethereum address derived from the device key
}

export interface VerifyAuthParams {
  challenge: AuthChallenge;
  response: AuthResponse;
  ttlMs?: number; // maximum challenge validity window (default: 30s)
}

export interface VerifyAuthResult {
  valid: boolean;
  identityId?: bigint;
  deviceAddress?: string;
  reason?: string;
}

export interface SessionInfo {
  exists: boolean;
  revoked: boolean;
  identityId?: bigint;
  devicePubKey?: string;
  createdAt?: Date;
}

export interface DeviceStatus {
  exists: boolean;
  active: boolean;
  label?: string;
  identityId?: bigint;
  addedAt?: Date;
}

export interface RegisterSessionParams {
  nonce: string;
  identityId: bigint;
  devicePubKey: string;
  sessionSignature: string; // 65-byte hex from personal_sign over the session hash
  relayerPrivateKey: `0x${string}`;
}

export interface RegisterSessionResult {
  txHash: `0x${string}`;
  sessionHash: `0x${string}`; // keccak256(nonce) — the on-chain session identifier
}

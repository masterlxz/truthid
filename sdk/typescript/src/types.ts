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
  // personal_sign over keccak256(nonce) — the mobile always sends this alongside
  // the login signature. Optional here only because a hand-built AuthResponse
  // (e.g. in tests) might omit it; the real mobile client never does.
  sessionSignature?: string;
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

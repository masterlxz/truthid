export type Network = "base-sepolia" | "base-mainnet";

export interface TruthIDClientConfig {
  network: Network;
  rpcUrl?: string;
}

// Formato exato que o mobile recebe e assina via WebSocket
export interface AuthChallenge {
  type: "challenge";
  nonce: string;
  issuedAt: number; // timestamp Unix em ms
  origin: string;
}

// Resposta enviada pelo mobile após o usuário aprovar
export interface AuthResponse {
  approved: boolean;
  nonce: string;
  signature: string;     // assinatura secp256k1 em hex ("0x...")
  deviceAddress: string; // endereço Ethereum da chave do device
}

export interface VerifyAuthParams {
  challenge: AuthChallenge;
  response: AuthResponse;
  ttlMs?: number; // tempo máximo de validade do challenge (padrão: 30s)
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

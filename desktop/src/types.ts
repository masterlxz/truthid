export type DeviceInfo = {
  identityId: bigint;
  pubKey: string;
  label: string;
  addedAt: bigint;
  revoked: boolean;
  exists: boolean;
};

export type PinningProvider = {
  name: string;
  kind: "kubo" | "psa";
  endpoint_url: string;
  api_key: string;
};

export type VaultEntry = {
  id: string;
  site: string;
  url: string;
  username: string;
  password: string;
  notes: string;
  profiles: string[];
  /** Segredo TOTP (RFC 6238) em base32, se 2FA estiver configurado pra esta entrada. */
  totp_secret?: string;
  created_at: number;
  updated_at: number;
};

export type PinResult = {
  cid: string;
  content_hash: string;
  providers_ok: string[];
  providers_failed: string[];
};

export type DeviceVaultPermission = {
  pub_key: string;
  can_write: boolean;
};

export type SmartAccountActivityType =
  | "session_created"
  | "session_revoked"
  | "session_revoked_all"
  | "device_registered"
  | "device_revoked"
  | "vault_updated";

export type SmartAccountActivity = {
  type: SmartAccountActivityType;
  hash: `0x${string}`;
  blockNumber: bigint;
  logIndex: number;
  timestamp: number;
  costWei: bigint;
};

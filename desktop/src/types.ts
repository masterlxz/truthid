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

export type Passkey = {
  rp_id: string;
  credential_id_b64: string;
  user_handle_b64: string;
  private_key_hex: string;
  sign_count: number;
  created_at: number;
};

/** Fase 15 — discriminante de tipo. Ausente em blobs antigos == "credential". */
export type EntryType = "credential" | "document" | "address" | "creditCard";

export type CardNetwork =
  | "visa"
  | "mastercard"
  | "amex"
  | "elo"
  | "hipercard"
  | "other";

export type DocumentData = {
  name: string;
  file_name: string;
  file_data: string;
  file_size_bytes: number;
  mime_type: string;
};

export type AddressData = {
  label: string;
  full_name: string;
  street: string;
  number: string;
  complement?: string;
  neighborhood: string;
  city: string;
  state: string;
  zip_code: string;
  country: string;
  phone?: string;
};

export type CreditCardData = {
  label: string;
  card_holder_name: string;
  /** Cifra individual extra fica pra 15.8 — hoje viaja em texto plano dentro do blob já cifrado. */
  card_number: string;
  expiry_month: string;
  expiry_year: string;
  cvv: string;
  bank?: string;
  card_network: CardNetwork;
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
  /** Credencial WebAuthn (passkey) da entrada, se o usuário gerou uma. */
  passkey?: Passkey;
  /** Favorito — sincroniza entre devices, trocado via vault_set_favorite. */
  favorite: boolean;
  /** Fase 15: tipo da entrada. Só o grupo correspondente (document/address/credit_card) deve vir preenchido. */
  type: EntryType;
  document?: DocumentData;
  address?: AddressData;
  credit_card?: CreditCardData;
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

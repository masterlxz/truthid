// Deterministic message for RFC 6979 vault key derivation.
// Same wallet + same message = same key on any device.
export const VAULT_KEY_MESSAGE = "TruthID Vault Key v1";
export const IDENTITY_REGISTRY_ADDRESS =
  "0x1313C576403F89eE265C880b33373d5DFB504cF2" as const;

export const IDENTITY_REGISTRY_ABI = [
  {
    type: "function",
    name: "createIdentity",
    inputs: [
      { name: "username", type: "string" },
      { name: "controller", type: "address" },
      { name: "v", type: "uint8" },
      { name: "r", type: "bytes32" },
      { name: "s", type: "bytes32" },
    ],
    outputs: [{ name: "id", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isUsernameTaken",
    inputs: [{ name: "username", type: "string" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUsernameByController",
    inputs: [{ name: "controller", type: "address" }],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getIdentity",
    inputs: [{ name: "username", type: "string" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "username", type: "string" },
          { name: "controller", type: "address" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
] as const;

// ─── DeviceRegistry ────────────────────────────────────────────────────────────

export const DEVICE_REGISTRY_ADDRESS =
  "0x48e0862c43339f29ED850a59f5DBd08A4786EaDf" as const;

// Bloco de deploy na Base Mainnet (Sessão 70 — redeploy completo, débito #28).
// Fonte: contracts/broadcast/Deploy.s.sol/8453/run-1783205021432.json
export const DEVICE_REGISTRY_DEPLOY_BLOCK = 48_207_828n;

export const DEVICE_REGISTRY_ABI = [
  {
    type: "function",
    name: "commitDevice",
    inputs: [{ name: "commitment", type: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "registerDevice",
    inputs: [
      { name: "devicePubKey", type: "address" },
      { name: "label", type: "string" },
      { name: "salt", type: "bytes32" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "revokeDevice",
    inputs: [{ name: "devicePubKey", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isDeviceActive",
    inputs: [{ name: "devicePubKey", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getDevicesByIdentity",
    inputs: [{ name: "identityId", type: "uint256" }],
    outputs: [{ name: "", type: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getDevice",
    inputs: [{ name: "devicePubKey", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "identityId", type: "uint256" },
          { name: "pubKey", type: "address" },
          { name: "label", type: "string" },
          { name: "addedAt", type: "uint256" },
          { name: "revoked", type: "bool" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "DeviceRegistered",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "pubKey", type: "address", indexed: true },
      { name: "label", type: "string", indexed: false },
    ],
  },
  {
    type: "event",
    name: "DeviceRevoked",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "pubKey", type: "address", indexed: true },
    ],
  },
] as const;

// ─── SessionRegistry ───────────────────────────────────────────────────────────

export const SESSION_REGISTRY_ADDRESS =
  "0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776" as const;

// Bloco de deploy na Base Mainnet (Sessão 70 — redeploy completo, débito #28).
// Fonte: contracts/broadcast/DeploySessionRegistry.s.sol/8453/run-1783205056882.json
export const SESSION_REGISTRY_DEPLOY_BLOCK = 48_207_855n;

export const SESSION_REGISTRY_ABI = [
  {
    type: "function",
    name: "createSession",
    inputs: [
      { name: "hash", type: "bytes32" },
      { name: "identityId", type: "uint256" },
      { name: "devicePubKey", type: "address" },
      { name: "r", type: "bytes32" },
      { name: "s", type: "bytes32" },
      { name: "v", type: "uint8" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "revokeSession",
    inputs: [{ name: "hash", type: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "revokeAllSessions",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isSessionRevoked",
    inputs: [{ name: "hash", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getSessionsByIdentity",
    inputs: [{ name: "identityId", type: "uint256" }],
    outputs: [{ name: "", type: "bytes32[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getSession",
    inputs: [{ name: "hash", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "identityId", type: "uint256" },
          { name: "devicePubKey", type: "address" },
          { name: "createdAt", type: "uint256" },
          { name: "revoked", type: "bool" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "SessionCreated",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "hash", type: "bytes32", indexed: true },
      { name: "devicePubKey", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "SessionRevoked",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "hash", type: "bytes32", indexed: true },
    ],
  },
  {
    type: "event",
    name: "AllSessionsRevoked",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "revokedBefore", type: "uint256", indexed: false },
    ],
  },
] as const;

export const VAULT_REGISTRY_ADDRESS =
  "0x0000000000000000000000000000000000000000" as const;

// VaultRegistry ainda não deployado — sem constante de bloco de deploy; o
// scan de atividade da smart account (14.10) pula este contrato inteiramente
// enquanto o endereço acima for o zero address.

export const VAULT_REGISTRY_ABI = [
  {
    type: "function",
    name: "updateVault",
    inputs: [
      { name: "cid", type: "string" },
      { name: "contentHash", type: "bytes32" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "hasVault",
    inputs: [{ name: "identityId", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getVault",
    inputs: [{ name: "identityId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "cid", type: "string" },
          { name: "contentHash", type: "bytes32" },
          { name: "updatedAt", type: "uint256" },
          { name: "version", type: "uint256" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "VaultUpdated",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "cid", type: "string", indexed: false },
      { name: "contentHash", type: "bytes32", indexed: true },
      { name: "version", type: "uint256", indexed: false },
    ],
  },
] as const;

// ─── TruthIDAccount (smart account) ───────────────────────────────────────────

export const TRUTHID_ACCOUNT_ABI = [
  {
    type: "function",
    name: "execute",
    inputs: [
      { name: "dest", type: "address" },
      { name: "value", type: "uint256" },
      { name: "func", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "executeBatch",
    inputs: [
      { name: "dest", type: "address[]" },
      { name: "value", type: "uint256[]" },
      { name: "func", type: "bytes[]" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "addDevice",
    inputs: [{ name: "device", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "removeDevice",
    inputs: [{ name: "device", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "authorizedDevices",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

// ─── TruthIDAccountFactory ────────────────────────────────────────────────────

export { TRUTHID_ACCOUNT_FACTORY_ADDRESS as FACTORY_ADDRESS } from "./truthidAccount";

export const FACTORY_ABI = [
  {
    type: "function",
    name: "createAccount",
    inputs: [
      { name: "owner_", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ name: "ret", type: "address" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getAddress",
    inputs: [
      { name: "owner_", type: "address" },
      { name: "index", type: "uint256" },
    ],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
] as const;

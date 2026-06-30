export const IDENTITY_REGISTRY_ADDRESS =
  "0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17" as const;

export const IDENTITY_REGISTRY_ABI = [
  {
    type: "function",
    name: "createIdentity",
    inputs: [
      { name: "username", type: "string" },
      { name: "controller", type: "address" },
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
  "0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144" as const;

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
] as const;

// ─── SessionRegistry ───────────────────────────────────────────────────────────

export const SESSION_REGISTRY_ADDRESS =
  "0x24074587a2aFB3aa5491361BB0a5eBee90797D1B" as const;

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

// TODO: atualizar após deploy do VaultRegistry na Base Mainnet
export const VAULT_REGISTRY_ADDRESS =
  "0x0000000000000000000000000000000000000000" as const;

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

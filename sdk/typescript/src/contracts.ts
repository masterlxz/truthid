export const IDENTITY_REGISTRY_ADDRESSES = {
  "base-sepolia": "0x7582E1c55fAFF19619A6c0a8b6575855d4e933d0",
  "base-mainnet": "0xC11426fd1cB103bC56dD3263325b34f2AcEe9903",
} as const;

// Immutables of the TruthIDAccountFactory (ERC-4337 smart account), used to
// predict a controller address via CREATE2 before it's ever deployed — see
// smartAccount.ts. Same source as desktop/src/config/truthidAccount.ts.
export const SMART_ACCOUNT_FACTORY_ADDRESSES = {
  "base-sepolia": "0x490A82AD72705fA92e0BBc0Dc5A894883fE90a9E",
  "base-mainnet": "0x6b1a78656510f734c7072040000A428e125C50df",
} as const;

export const RECOVERY_MANAGER_ADDRESSES = {
  "base-sepolia": "0xC60AE3D7Fc7991A48B780E3bF2838027079204Ce",
  "base-mainnet": "0x1d51daD35Bd3562f8B56B334a9B8637873fE40e9",
} as const;

// ERC-4337 EntryPoint v0.7 — same canonical singleton address on every chain.
export const ENTRY_POINT_V07_ADDRESS =
  "0x0000000071727De22E5E9d8BAf0edAc6f37da032" as const;

export const IDENTITY_REGISTRY_ABI = [
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
  {
    type: "function",
    name: "getUsernameByController",
    inputs: [{ name: "controller", type: "address" }],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
] as const;

export const DEVICE_REGISTRY_ADDRESSES = {
  "base-sepolia": "0x867EA636FDF324B0Cc4a631C70421580e2Bbe91c",
  "base-mainnet": "0x4Fd53d70553df00D42c015EB35E2626cB80b1614",
} as const;

export const DEVICE_REGISTRY_ABI = [
  {
    type: "function",
    name: "isDeviceActive",
    inputs: [{ name: "devicePubKey", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
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

export const SESSION_REGISTRY_ADDRESSES = {
  "base-sepolia": "0xFE49Cec3a927136f7F18E521BF1547f00b09B17f",
  "base-mainnet": "0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df",
} as const;

export const SESSION_REGISTRY_ABI = [
  {
    type: "function",
    name: "isSessionRevoked",
    inputs: [{ name: "hash", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
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
] as const;

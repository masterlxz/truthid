export const IDENTITY_REGISTRY_ADDRESSES = {
  "base-sepolia": "0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998",
  "base-mainnet": "0x1313C576403F89eE265C880b33373d5DFB504cF2",
} as const;

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
  "base-sepolia": "0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d",
  "base-mainnet": "0x48e0862c43339f29ED850a59f5DBd08A4786EaDf",
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
  "base-sepolia": "0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65",
  "base-mainnet": "0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776",
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

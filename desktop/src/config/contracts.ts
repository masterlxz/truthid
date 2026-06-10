export const IDENTITY_REGISTRY_ADDRESS =
  "0xd4484aDD6DCd0919568B6365882cDB207fE27D9c" as const;

export const IDENTITY_REGISTRY_ABI = [
  {
    type: "function",
    name: "createIdentity",
    inputs: [{ name: "username", type: "string" }],
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
  "0xe87633b148cf7a7F6c60DdA84AD7f4D3a9eC187F" as const;

export const DEVICE_REGISTRY_ABI = [
  {
    type: "function",
    name: "registerDevice",
    inputs: [
      { name: "devicePubKey", type: "address" },
      { name: "label", type: "string" },
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

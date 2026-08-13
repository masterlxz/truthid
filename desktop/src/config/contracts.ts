export const IDENTITY_REGISTRY_ADDRESS =
  "0x97787D6EE3EfD76962dc7E3Bf143E659D9961962" as const;

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
  "0x937702CBABDab0EEBD1A29f0a7A658FeF4582543" as const;

// Bloco de deploy na Base Mainnet (débito #52 — redeploy em cascata com
// migração real de devices, ver migrateDevices() no contrato).
// Fonte: contracts/broadcast/Deploy.s.sol/8453/run-latest.json
export const DEVICE_REGISTRY_DEPLOY_BLOCK = 49_935_103n;

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
      { name: "encryptedVaultKey", type: "bytes" },
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
    type: "function",
    name: "deviceVaultKeys",
    inputs: [{ name: "devicePubKey", type: "address" }],
    outputs: [{ name: "", type: "bytes" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "updateDeviceVaultKey",
    inputs: [
      { name: "devicePubKey", type: "address" },
      { name: "newEncryptedVaultKey", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "DeviceRegistered",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "pubKey", type: "address", indexed: true },
      { name: "label", type: "string", indexed: false },
      { name: "encryptedVaultKey", type: "bytes", indexed: false },
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
  {
    type: "event",
    name: "DeviceVaultKeyUpdated",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "pubKey", type: "address", indexed: true },
    ],
  },
] as const;

// ─── SessionRegistry ───────────────────────────────────────────────────────────

export const SESSION_REGISTRY_ADDRESS =
  "0x8C65527eDA3ce7754Bf87B34aC4ec8ce74D647e2" as const;

// Ligada — o SessionRegistry novo (redeploy em cascata, débito #52) já
// verifica keccak256(chainId, address(this), hash) na assinatura de sessão
// (fix C4). Ver P26 em project/PENDING.md.
export const SESSION_DOMAIN_SEPARATION_ENABLED = true as const;

// Bloco de deploy na Base Mainnet (redeploy em cascata, débito #52).
// Fonte: contracts/broadcast/DeploySessionRegistry.s.sol/8453/run-latest.json
export const SESSION_REGISTRY_DEPLOY_BLOCK = 49_935_140n;

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

// ─── RecoveryManager (Social Recovery) ──────────────────────────────────────

// Endereço do RecoveryManager deployado na Base Mainnet.
// Fonte: contracts/broadcast/Deploy.s.sol/8453/run-latest.json
// Redeploy em cascata (débito #52) já com os fixes C1 (reentrância),
// C3 (revogação de devices), C5-C9.
export const RECOVERY_MANAGER_ADDRESS =
  "0x42Ca394c23aB027e877B9900B384f59E2Af23470" as const;

export const RECOVERY_MANAGER_ABI = [
  {
    type: "function",
    name: "configureGuardians",
    inputs: [
      { name: "username", type: "string" },
      { name: "guardians", type: "address[]" },
      { name: "threshold", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "proposeRecovery",
    inputs: [
      { name: "username", type: "string" },
      { name: "newController", type: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "approveRecovery",
    inputs: [{ name: "username", type: "string" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "executeRecovery",
    inputs: [{ name: "username", type: "string" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "cancelRecovery",
    inputs: [{ name: "username", type: "string" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getGuardianConfig",
    inputs: [{ name: "username", type: "string" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "guardians", type: "address[]" },
          { name: "threshold", type: "uint256" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getProposal",
    inputs: [{ name: "username", type: "string" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "proposedBy", type: "address" },
          { name: "newController", type: "address" },
          { name: "proposedAt", type: "uint256" },
          { name: "approvalCount", type: "uint256" },
          { name: "executed", type: "bool" },
          { name: "cancelled", type: "bool" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "hasGuardianApproved",
    inputs: [
      { name: "username", type: "string" },
      { name: "guardian", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "TIMELOCK",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "GuardiansConfigured",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "guardians", type: "address[]", indexed: false },
      { name: "threshold", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RecoveryProposed",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "proposedBy", type: "address", indexed: true },
      { name: "newController", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "RecoveryApproved",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "guardian", type: "address", indexed: true },
      { name: "approvalCount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RecoveryExecuted",
    inputs: [
      { name: "identityId", type: "uint256", indexed: true },
      { name: "newController", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "RecoveryCancelled",
    inputs: [{ name: "identityId", type: "uint256", indexed: true }],
  },
] as const;

export const VAULT_REGISTRY_ADDRESS =
  "0x07449b0c8dAE1252f59A5C0992D1413113a849B4" as const;

// Bloco de deploy na Base Mainnet (redeploy em cascata, débito #52).
// Fonte: contracts/broadcast/DeployVaultRegistry.s.sol/8453/run-latest.json
export const VAULT_REGISTRY_DEPLOY_BLOCK = 49_935_166n;

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

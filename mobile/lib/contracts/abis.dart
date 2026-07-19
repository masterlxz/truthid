// ABI fragments used by the mobile app.
// Only the functions actually called are listed — no need for the full ABI.
// Source: contracts/src/SessionRegistry.sol, DeviceRegistry.sol, IdentityRegistry.sol
// Update here when the contract interface changes.

const String sessionRegistryAbi = '''[
  {
    "type": "function",
    "name": "getSessionsByIdentity",
    "inputs": [{"name": "identityId", "type": "uint256"}],
    "outputs": [{"name": "", "type": "bytes32[]"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getSession",
    "inputs": [{"name": "hash", "type": "bytes32"}],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        {"name": "identityId", "type": "uint256"},
        {"name": "devicePubKey", "type": "address"},
        {"name": "createdAt", "type": "uint256"},
        {"name": "revoked", "type": "bool"},
        {"name": "exists", "type": "bool"}
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isSessionRevoked",
    "inputs": [{"name": "hash", "type": "bytes32"}],
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "createSession",
    "inputs": [
      {"name": "hash", "type": "bytes32"},
      {"name": "identityId", "type": "uint256"},
      {"name": "devicePubKey", "type": "address"},
      {"name": "r", "type": "bytes32"},
      {"name": "s", "type": "bytes32"},
      {"name": "v", "type": "uint8"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "revokeSession",
    "inputs": [{"name": "hash", "type": "bytes32"}],
    "outputs": [],
    "stateMutability": "nonpayable"
  }
]''';

const String identityRegistryAbi = '''[
  {
    "type": "event",
    "name": "IdentityCreated",
    "inputs": [
      {"name": "id", "type": "uint256", "indexed": true},
      {"name": "username", "type": "string", "indexed": false},
      {"name": "controller", "type": "address", "indexed": true}
    ]
  },
  {
    "type": "function",
    "name": "getIdentity",
    "inputs": [{"name": "username", "type": "string"}],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        {"name": "id", "type": "uint256"},
        {"name": "username", "type": "string"},
        {"name": "controller", "type": "address"},
        {"name": "exists", "type": "bool"}
      ]
    }],
    "stateMutability": "view"
  }
]''';

// TruthIDAccount (smart account ERC-4337) — só `execute`, usado pela 14.9.5 pra
// encapsular a chamada a SessionRegistry.createSession dentro da UserOperation.
// Source: contracts/src/TruthIDAccount.sol
const String truthidAccountAbi = '''[
  {
    "type": "function",
    "name": "execute",
    "inputs": [
      {"name": "dest", "type": "address"},
      {"name": "value", "type": "uint256"},
      {"name": "func", "type": "bytes"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  }
]''';

// EntryPoint v0.7 (eth-infinitism) — só `getNonce`, usado pela 14.9.5 pra ler o
// nonce atual da smart account antes de montar a UserOperation.
const String entryPointAbi = '''[
  {
    "type": "function",
    "name": "getNonce",
    "inputs": [
      {"name": "sender", "type": "address"},
      {"name": "key", "type": "uint192"}
    ],
    "outputs": [{"name": "nonce", "type": "uint256"}],
    "stateMutability": "view"
  }
]''';

// VaultRegistry — só `updateVault`, usado pela publicação do vault a partir
// do Mobile (Sessão 97). Roteado via TruthIDAccount.execute(), mesmo padrão
// já usado pelo Desktop (desktop/src/hooks/useVaultPublish.ts).
// Source: contracts/src/VaultRegistry.sol
const String vaultRegistryAbi = '''[
  {
    "type": "function",
    "name": "updateVault",
    "inputs": [
      {"name": "cid", "type": "string"},
      {"name": "contentHash", "type": "bytes32"}
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  }
]''';

const String deviceRegistryAbi = '''[
  {
    "type": "function",
    "name": "getDevice",
    "inputs": [{"name": "devicePubKey", "type": "address"}],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        {"name": "identityId", "type": "uint256"},
        {"name": "pubKey", "type": "address"},
        {"name": "label", "type": "string"},
        {"name": "addedAt", "type": "uint256"},
        {"name": "revoked", "type": "bool"},
        {"name": "exists", "type": "bool"}
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "deviceVaultKeys",
    "inputs": [{"name": "", "type": "address"}],
    "outputs": [{"name": "", "type": "bytes"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getDevicesByIdentity",
    "inputs": [{"name": "identityId", "type": "uint256"}],
    "outputs": [{"name": "", "type": "address[]"}],
    "stateMutability": "view"
  }
]''';
